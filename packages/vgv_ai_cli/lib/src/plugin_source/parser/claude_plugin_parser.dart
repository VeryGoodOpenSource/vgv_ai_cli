import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/format/format.dart';
import 'package:vgv_ai_cli/src/plugin_source/model/model.dart';
import 'package:vgv_ai_cli/src/plugin_source/parser/plugin_parser.dart';

/// {@template claude_plugin_parser}
/// Reads a Claude Code plugin directory into the harness-neutral model.
///
/// The single place that knows what "Claude-specific" means: the
/// `user-invocable` default, how `allowed-tools` is written, and the
/// `${CLAUDE_PLUGIN_ROOT}` hook placeholder. It tolerates the real, mutually
/// inconsistent shapes the two plugins ship, not the documented ones.
/// {@endtemplate}
class const ClaudePluginParser() implements PluginParser {
  @override
  PluginAssets parse(Directory root) => PluginAssets(
    skills: _readSkills(root.childDirectory('skills')),
    agents: _readAgents(root.childDirectory('agents')),
    mcpServers: _readMcpServers(root.childFile('.mcp.json')),
    hooks: _readHooks(root.childDirectory('hooks')),
  );

  /// Whether a skill with this [frontmatter] should be emitted as a command.
  ///
  /// The Flutter plugin omits `user-invocable` entirely yet its skills are
  /// invocable, so an absent key means `true`.
  static bool userInvocableOf(Frontmatter frontmatter) =>
      frontmatter.config.boolean('user-invocable') ?? true;

  /// The tools a skill with this [frontmatter] declares it needs.
  ///
  /// Read from `allowed-tools`, falling back to `tools`, then tokenized by
  /// [tokenizeTools].
  static List<String> allowedToolsOf(Frontmatter frontmatter) => tokenizeTools(
    frontmatter.config.string('allowed-tools') ??
        frontmatter.config.string('tools'),
  );

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

  /// The [frontmatter] values safe to write for any harness.
  ///
  /// Keeps exactly [SkillAsset.portableKeys]. Claude adds keys such as
  /// `effort`, `model`, `when_to_use` and `user-invocable` that no other
  /// harness reads; they are interpreted where they matter and dropped here.
  static Map<String, Object?> portableFrontmatterOf(
    Frontmatter frontmatter,
  ) => {
    for (final entry in frontmatter.config.entries)
      if (SkillAsset.portableKeys.contains(entry.key)) entry.key: entry.value,
  };

  /// One tool name, plus an optional parenthesized scope that may itself
  /// contain spaces, commas and slashes.
  static final _toolPattern = RegExp(r'[\w.-]+(?:\([^)]*\))?');

  /// Claude's own name for the plugin root inside a hook command. Rewritten to
  /// the neutral [HookCommand.pluginRoot] so translators never see it.
  static const _claudePluginRoot = r'${CLAUDE_PLUGIN_ROOT}';

  List<SkillAsset> _readSkills(Directory skillsDir) {
    if (!skillsDir.existsSync()) return const [];

    final skills = <SkillAsset>[];
    for (final entity in skillsDir.listSync().whereType<Directory>()) {
      final file = entity.childFile('SKILL.md');
      // `skills/shared/` pools references for the other skills and has no
      // SKILL.md, so it is not a skill. It is a symlink target though, so it
      // must survive any later copy.
      if (!file.existsSync()) continue;

      final frontmatter = Frontmatter.parse(
        file.readAsStringSync(),
        path: file.path,
      );
      skills.add(
        SkillAsset(
          name: frontmatter.name ?? p.basename(entity.path),
          description: frontmatter.description,
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

  List<AgentAsset> _readAgents(Directory agentsDir) {
    if (!agentsDir.existsSync()) return const [];

    final agents = <AgentAsset>[];
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
        AgentAsset(
          name: frontmatter.name ?? p.basenameWithoutExtension(file.path),
          description: frontmatter.description,
          body: frontmatter.body,
          skills: frontmatter.skills,
        ),
      );
    }
    agents.sort((a, b) => a.name.compareTo(b.name));
    return agents;
  }

  /// Reads `hooks/hooks.json`, whose shape is an event map of registrations:
  /// `{"hooks": {"<Event>": [{"matcher"?, "hooks": [{type, command}]}]}}`.
  ///
  /// Every level is tolerated as absent or the wrong type rather than assumed,
  /// because a plugin may ship no hooks at all.
  List<HookAsset> _readHooks(Directory hooksDir) {
    final file = hooksDir.childFile('hooks.json');
    if (!file.existsSync()) return const [];

    final events = _readJsonObject(file).child('hooks');
    if (events == null) return const [];

    final assets = <HookAsset>[];
    for (final event in events.entries) {
      for (final registration in ConfigMap.maps(event.value)) {
        final commands = _readHookCommands(registration['hooks']);
        if (commands.isEmpty) continue;

        // A matcher that is not a string is meaningless; drop it rather than
        // stringify it, matching the tolerant shape the plugins are written in.
        final matcher = registration['matcher'];
        assets.add(
          HookAsset(
            event: event.key,
            matcher: matcher is String ? matcher : null,
            commands: commands,
            directory: hooksDir,
          ),
        );
      }
    }
    return assets;
  }

  List<HookCommand> _readHookCommands(Object? raw) {
    final commands = <HookCommand>[];
    for (final entry in ConfigMap.maps(raw)) {
      final command = entry['command'];
      if (command is! String) continue;

      commands.add(
        HookCommand(
          type: entry.string('type') ?? 'command',
          command: command.replaceAll(
            _claudePluginRoot,
            HookCommand.pluginRoot,
          ),
          timeout: entry.integer('timeout'),
        ),
      );
    }
    return commands;
  }

  Map<String, MCPServer> _readMcpServers(File mcpFile) {
    if (!mcpFile.existsSync()) return const {};

    final servers = _readJsonObject(mcpFile).child('mcpServers');
    if (servers == null) return const {};

    final result = <String, MCPServer>{};
    for (final entry in servers.entries) {
      // Anything that is not an object (e.g. a bare string) is not a server
      // declaration and is skipped.
      final config = servers.child(entry.key);
      if (config == null) continue;

      final server = _mcpServer(config);
      if (server != null) result[entry.key] = server;
    }
    return result;
  }

  /// Discriminates a server declaration by shape: a `url` makes it remote, a
  /// `command` makes it local. A declaration with neither is not a valid MCP
  /// server, so it is dropped ([MCPServer] has no unknown variant).
  MCPServer? _mcpServer(ConfigMap config) {
    final url = config.string('url');
    if (url != null) {
      return RemoteMCPServer(
        url: url,
        headers: _stringMap(config.child('headers')),
      );
    }

    final command = config.string('command');
    if (command != null) {
      return LocalMCPServer(
        command: command,
        args: config.stringList('args'),
        env: _stringMap(config.child('env')),
      );
    }

    return null;
  }

  /// Flattens a nested config block into a string-to-string map, stringifying
  /// each value. Used for `env` and `headers`, both of which are string maps.
  Map<String, String> _stringMap(ConfigMap? config) => {
    if (config != null)
      for (final entry in config.entries) entry.key: '${entry.value}',
  };

  ConfigMap _readJsonObject(File file) =>
      ConfigMap.parseJson(file.readAsStringSync(), path: file.path);
}
