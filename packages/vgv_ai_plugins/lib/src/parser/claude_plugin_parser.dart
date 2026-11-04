import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_plugins/src/format/format.dart';
import 'package:vgv_ai_plugins/src/model/model.dart';
import 'package:vgv_ai_plugins/src/parser/claude_schemas.dart';
import 'package:vgv_ai_plugins/src/parser/plugin_parser.dart';

/// {@template claude_plugin_parser}
/// Reads a Claude Code plugin directory into the harness-neutral model.
///
/// The single place that knows what "Claude-specific" means: the
/// `user-invocable` default, how `allowed-tools` is written, and the
/// `${CLAUDE_PLUGIN_ROOT}` placeholder. Each file is validated against
/// its shape in `claude_schemas.dart`, which admits the real, mutually
/// inconsistent shapes the pinned plugins ship and throws on anything else.
/// {@endtemplate}
class const ClaudePluginParser() implements PluginParser {
  /// {@macro claude_plugin_parser}
  this;

  @override
  PluginAssets parse(Directory root) {
    // Read only once a hook or a rooted body needs it, so a plugin with
    // neither needs no manifest.
    late final plugin = _pluginName(root);
    String rooted(String body) => body.replaceAllMapped(
      _rootedPath,
      (match) => '${PluginPath.placeholder}/$plugin/${match[1]}',
    );

    final skills = _readSkills(root.childDirectory('skills'));
    final agents = _readAgents(root.childDirectory('agents'));
    final events = _readHookEvents(root);
    final bodies = [
      for (final skill in skills) skill.body,
      for (final agent in agents) agent.asset.body,
    ];
    return PluginAssets(
      skills: [for (final skill in skills) skill.withBody(rooted(skill.body))],
      agents: [
        for (final agent in agents)
          agent.asset.withBody(rooted(agent.asset.body)),
      ],
      mcpServers: _readMcpServers(root.childFile('.mcp.json')),
      paths: [
        for (final path in _namedPaths(bodies))
          PluginPath(plugin: plugin, pluginRoot: root, path: path),
      ],
      hooks: [
        if (events != null)
          ..._readRegistrations(events, plugin: plugin, root: root),
        // Hooks an agent declares for itself, in the shape of hooks.json.
        for (final agent in agents)
          if (agent.hooks case final hooks?)
            ..._readRegistrations(
              hooks,
              plugin: plugin,
              root: root,
              agent: agent.asset.name,
            ),
      ],
    );
  }

  /// Whether a skill with this [frontmatter] should be emitted as a command.
  ///
  /// The Flutter plugin omits `user-invocable` entirely yet its skills are
  /// invocable, so an absent key means `true`.
  static bool userInvocableOf(SkillFrontmatter frontmatter) =>
      frontmatter.userInvocable ?? true;

  /// The tools a skill with this [frontmatter] declares it needs.
  ///
  /// Read from `allowed-tools`, falling back to `tools`, then tokenized by
  /// [tokenizeTools].
  static List<String> allowedToolsOf(SkillFrontmatter frontmatter) =>
      tokenizeTools(frontmatter.allowedTools ?? frontmatter.tools);

  /// Splits Claude's `allowed-tools` value into individual tool names.
  ///
  /// Matched rather than split, because a tool may carry a parenthesized scope
  /// that contains the very separators a split would break on. Five wingspan
  /// skills ship entries like `Bash(git push *)` and `Bash(rm -rf docs/x/)`,
  /// which splitting on whitespace turns into `Bash(git`, `push` and `*)`.
  ///
  /// Separators are either spaces or commas: every skill uses spaces except
  /// `animations`, which uses commas.
  static List<String> tokenizeTools(String? raw) {
    if (raw == null) return const [];
    return _toolPattern.allMatches(raw).map((match) => match[0]!).toList();
  }

  /// The description every harness reads, with the trigger phrases folded in.
  ///
  /// Claude Code appends `when_to_use` to the description when it builds its
  /// skill index, so a skill is free to keep its triggers there. No other
  /// harness reads the key, and it is outside the Agent Skills key set, so
  /// folding is the only way those phrases survive translation.
  static String descriptionOf(SkillFrontmatter frontmatter) => [
    frontmatter.description,
    ?frontmatter.whenToUse,
  ].where((part) => part.isNotEmpty).join(' - ');

  /// The [frontmatter] values safe to write for any harness.
  ///
  /// Keeps exactly [SkillAsset.portableKeys]. Claude adds keys such as
  /// `effort`, `model`, `when_to_use` and `user-invocable` that no other
  /// harness reads; they are interpreted where they matter and dropped here.
  static Map<String, Object?> portableFrontmatterOf(
    SkillFrontmatter frontmatter,
  ) => {
    for (final entry in frontmatter.values.entries)
      if (SkillAsset.portableKeys.contains(entry.key)) entry.key: entry.value,
    // Rewrites the description in place, keeping its position. Only a skill
    // that declares `when_to_use` is touched, so one that does not renders
    // exactly as it was written.
    if (frontmatter.whenToUse != null)
      'description': descriptionOf(frontmatter),
  };

  /// What a skill or agent may be named. The name becomes a file or
  /// directory name under the user's home, so a separator, a `..` or a
  /// character Windows refuses would write somewhere it must not.
  static final _namePattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// One tool name, plus an optional parenthesized scope that may itself
  /// contain spaces, commas and slashes.
  static final _toolPattern = RegExp(r'[\w.-]+(?:\([^)]*\))?');

  /// Claude's name for the plugin root. In a hook command it becomes
  /// [HookCommand.rootPlaceholder]; in a skill or agent body, only a path
  /// [_rootedPath] matches becomes the plugin's folder under
  /// [PluginPath.placeholder]. A script's own use of the variable at run
  /// time stays as written.
  static const _claudePluginRoot = r'${CLAUDE_PLUGIN_ROOT}';

  /// A path under the plugin root a body names. No segment may start with a
  /// dot, so a path can never climb out of the root, and it ends where a
  /// character no path segment holds does, such as a space or a backtick.
  /// A bare root, or one followed by `..` or a hidden name, is left as
  /// written, since nothing is copied for it.
  static final _rootedPath = RegExp(
    '${RegExp.escape(_claudePluginRoot)}/'
    r'([\w-][\w.-]*(?:/[\w-][\w.-]*)*)',
  );

  /// Every path under the plugin root that [bodies] name, once each. A
  /// sentence that ends on a path leaves its full stop out of it.
  static Set<String> _namedPaths(List<String> bodies) => {
    for (final body in bodies)
      for (final match in _rootedPath.allMatches(body))
        match[1]!.replaceFirst(_trailingDots, ''),
  };

  /// The full stop of a sentence that ends on a path.
  static final _trailingDots = RegExp(r'\.+$');

  /// What a plugin may be named. Its name becomes a folder in every copy of
  /// its files and hooks, and falls back to the cache directory's name, such
  /// as `0.0.5`, so it is looser than [_namePattern].
  static final _pluginNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// [name], once it is known to be safe as a file name.
  ///
  /// [path] names the file in the [PluginParseException] otherwise.
  String _validName(String name, {required String path}) {
    if (_namePattern.hasMatch(name)) return name;
    throw PluginParseException(
      path,
      'name "$name" may only use lowercase letters, digits, "-" and "_"',
    );
  }

  List<SkillAsset> _readSkills(Directory skillsDir) {
    if (!skillsDir.existsSync()) return const [];

    final skills = <SkillAsset>[];
    for (final entity in skillsDir.listSync().whereType<Directory>()) {
      final file = entity.childFile('SKILL.md');
      // `skills/shared/` pools references for the other skills and has no
      // SKILL.md, so it is not a skill. It is a symlink target though, so it
      // must survive any later copy.
      if (!file.existsSync()) continue;

      final frontmatter = SkillFrontmatter.decode(
        Frontmatter.parse(file.readAsStringSync(), path: file.path),
        path: file.path,
      );
      skills.add(
        SkillAsset(
          name: _validName(
            frontmatter.name ?? p.basename(entity.path),
            path: file.path,
          ),
          description: descriptionOf(frontmatter),
          body: frontmatter.body,
          userInvocable: userInvocableOf(frontmatter),
          allowedTools: allowedToolsOf(frontmatter),
          portableFrontmatter: portableFrontmatterOf(frontmatter),
          directory: entity,
        ),
      );
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  List<_AgentFile> _readAgents(Directory agentsDir) {
    if (!agentsDir.existsSync()) return const [];

    final agents = <_AgentFile>[];
    // Wingspan nests agents under a category directory and the Flutter plugin
    // does not, so recurse and flatten. followLinks is off so a cycle cannot
    // hang the walk; there are no symlinks under agents/ in either plugin.
    final entities = agentsDir.listSync(recursive: true, followLinks: false);
    for (final file in entities.whereType<File>()) {
      if (p.extension(file.path) != '.md') continue;

      final frontmatter = Frontmatter.parse(
        file.readAsStringSync(),
        path: file.path,
      );
      agents.add(
        _AgentFile(
          asset: AgentAsset(
            name: _validName(
              frontmatter.name ?? p.basenameWithoutExtension(file.path),
              path: file.path,
            ),
            description: frontmatter.description,
            body: frontmatter.body,
            skills: frontmatter.skills,
          ),
          hooks: HooksJson.decode(frontmatter.values, path: file.path).events,
        ),
      );
    }
    agents.sort((a, b) => a.asset.name.compareTo(b.asset.name));
    return agents;
  }

  /// The registrations of `hooks/hooks.json` under [root], by event, or null
  /// when the plugin ships none.
  Map<String, List<HookRegistrationJson>>? _readHookEvents(Directory root) {
    final file = root.childDirectory('hooks').childFile('hooks.json');
    if (!file.existsSync()) return null;

    return HooksJson.decodeJson(
      file.readAsStringSync(),
      path: file.path,
    ).events;
  }

  /// The hooks under [events], declared by [plugin] at [root] and scoped to
  /// [agent] when one declared them.
  List<HookAsset> _readRegistrations(
    Map<String, List<HookRegistrationJson>> events, {
    required String plugin,
    required Directory root,
    String? agent,
  }) => [
    for (final MapEntry(key: event, value: registrations) in events.entries)
      for (final registration in registrations)
        ?_readRegistration(
          event,
          registration,
          plugin: plugin,
          root: root,
          agent: agent,
        ),
  ];

  /// One registration under [event], or null when it runs nothing.
  HookAsset? _readRegistration(
    String event,
    HookRegistrationJson registration, {
    required String plugin,
    required Directory root,
    required String? agent,
  }) {
    final commands = _readHookCommands(registration.hooks);
    if (commands.isEmpty) return null;

    return HookAsset(
      event: event,
      matcher: registration.matcher,
      commands: commands,
      plugin: plugin,
      pluginRoot: root,
      agent: agent,
    );
  }

  /// The manifest's name, or the directory's without one. The cache names a
  /// directory after the version, so the manifest is what says vgv-wingspan.
  /// A name that is not safe as a folder name is a [PluginParseException].
  String _pluginName(Directory root) {
    final manifest = root
        .childDirectory('.claude-plugin')
        .childFile('plugin.json');
    final declared = manifest.existsSync()
        ? PluginManifestJson.decodeJson(
            manifest.readAsStringSync(),
            path: manifest.path,
          ).name
        : null;
    final name = declared ?? p.basename(root.path);
    if (_pluginNamePattern.hasMatch(name)) return name;
    throw PluginParseException(
      manifest.path,
      'plugin name "$name" must start with a letter or digit and may only '
      'use letters, digits, ".", "-" and "_"',
    );
  }

  /// The hooks of one registration that run a command, the only kind a
  /// harness can translate.
  List<HookCommand> _readHookCommands(List<HookJson> hooks) => [
    for (final hook in hooks)
      if (hook.command case final command?)
        HookCommand(
          type: hook.type ?? 'command',
          command: command.replaceAll(
            _claudePluginRoot,
            HookCommand.rootPlaceholder,
          ),
          timeout: hook.timeout,
        ),
  ];

  List<MCPServer> _readMcpServers(File mcpFile) {
    if (!mcpFile.existsSync()) return const [];

    final file = McpFileJson.decodeJson(
      mcpFile.readAsStringSync(),
      path: mcpFile.path,
    );
    return [
      for (final MapEntry(key: name, value: server) in file.servers.entries)
        _mcpServer(name, server, path: mcpFile.path),
    ];
  }

  /// Discriminates a server declaration by shape: a `url` makes it remote, a
  /// `command` makes it local. A declaration with neither is not a valid MCP
  /// server ([MCPServer] has no unknown variant), so it throws, naming the
  /// server and the file at [path].
  MCPServer _mcpServer(
    String name,
    McpServerJson server, {
    required String path,
  }) => switch (server) {
    McpServerJson(:final url?) => RemoteMCPServer(
      name: name,
      url: url,
      headers: server.headers,
    ),
    McpServerJson(:final command?) => LocalMCPServer(
      name: name,
      command: command,
      args: server.args,
      env: server.env,
    ),
    _ => throw PluginParseException(
      path,
      '${jsonPointer('#/mcpServers', name)}: declares neither a url nor a '
      'command',
    ),
  };
}

/// An agent file: the asset, and the hooks its frontmatter declares for it.
class const _AgentFile({
  required final AgentAsset asset,
  final Map<String, List<HookRegistrationJson>>? hooks,
});
