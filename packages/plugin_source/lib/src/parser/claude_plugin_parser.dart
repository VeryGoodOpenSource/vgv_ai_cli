import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/src/format/format.dart';
import 'package:plugin_source/src/model/model.dart';
import 'package:plugin_source/src/parser/claude_schemas.dart';
import 'package:plugin_source/src/parser/plugin_parser.dart';

/// {@template claude_plugin_parser}
/// Reads a Claude Code plugin directory into the harness-neutral model.
///
/// The single place that knows what "Claude-specific" means: the
/// `user-invocable` default, how `allowed-tools` is written, and the
/// `${CLAUDE_PLUGIN_ROOT}` hook placeholder. Each file is validated against
/// its shape in `claude_schemas.dart`, which admits the real, mutually
/// inconsistent shapes the two plugins ship and throws on anything else.
/// {@endtemplate}
class const ClaudePluginParser() implements PluginParser {
  @override
  PluginAssets parse(Directory root) {
    final agents = _readAgents(root.childDirectory('agents'));
    final events = _readHookEvents(root);
    final scoped = [
      for (final agent in agents)
        if (agent.hooks != null) agent,
    ];
    // Only a hook needs the name, so a hookless plugin needs no manifest.
    final plugin = events == null && scoped.isEmpty ? null : _pluginName(root);
    return PluginAssets(
      skills: _readSkills(root.childDirectory('skills')),
      agents: [for (final agent in agents) agent.asset],
      mcpServers: _readMcpServers(root.childFile('.mcp.json')),
      hooks: [
        if (events != null)
          ..._readRegistrations(events, plugin: plugin!, root: root),
        // Hooks an agent declares for itself, in the shape of hooks.json.
        for (final agent in scoped)
          ..._readRegistrations(
            agent.hooks!,
            plugin: plugin!,
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

  /// Claude's name for the plugin root in a hook command, rewritten to
  /// [HookCommand.rootPlaceholder]. A script's own use of the variable at
  /// run time stays as written.
  static const _claudePluginRoot = r'${CLAUDE_PLUGIN_ROOT}';

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
    return declared ?? p.basename(root.path);
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
