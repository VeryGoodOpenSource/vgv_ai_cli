import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/frontmatter.dart';
import 'package:vgv_ai_cli/src/plugin_source/hooks.dart';

/// Frontmatter keys Claude Code understands that no other harness does.
///
/// Packaging a skill with these breaks it elsewhere, so they are dropped when
/// a skill is written to the canonical location.
///
/// Every entry is observed in the real plugins. `compatibility` is deliberately
/// absent: it is prose such as "Designed for Claude Code (or similar
/// products)", harmless to carry, and dropping it would lose information no
/// other key holds.
const claudeOnlyKeys = <String>{
  'user-invocable',
  'disable-model-invocation',
  'effort',
  'when_to_use',
};

/// {@template skill_asset}
/// A skill resolved from a plugin.
///
/// [directory] is where the skill was read from, so `references/` and
/// `scripts/` can be copied alongside it.
/// {@endtemplate}
class const SkillAsset({
  required final String name,
  required final Frontmatter frontmatter,
  required final Directory directory,
}) {
  /// A one-line description for an index table.
  String get description => frontmatter.description;

  /// Whether the skill should be emitted as a command.
  bool get userInvocable => frontmatter.userInvocable;

  /// The markdown body, without frontmatter.
  String get body => frontmatter.body;

  /// Frontmatter safe to write for a non-Claude harness.
  Map<String, Object?> get portableFrontmatter => {
    for (final entry in frontmatter.values.entries)
      if (!claudeOnlyKeys.contains(entry.key)) entry.key: entry.value,
  };
}

/// {@template agent_asset}
/// A subagent resolved from a plugin.
/// {@endtemplate}
class const AgentAsset({
  required final String name,
  required final Frontmatter frontmatter,
}) {
  /// A one-line description for an index table.
  String get description => frontmatter.description;

  /// The agent prompt.
  String get body => frontmatter.body;

  /// Skills the agent expects to have loaded.
  ///
  /// Claude Code resolves these itself. Every other harness needs them wired
  /// in at install time.
  List<String> get skills => frontmatter.skills;
}

/// {@template plugin_assets}
/// Everything one or more plugins contribute, in a harness-neutral shape.
/// {@endtemplate}
class const PluginAssets({
  required final List<SkillAsset> skills,
  required final List<AgentAsset> agents,
  required final Map<String, Map<String, Object?>> mcpServers,
  final List<HookAsset> hooks = const [],
}) {
  /// An empty set of assets.
  static const empty = PluginAssets(
    skills: [],
    agents: [],
    mcpServers: <String, Map<String, Object?>>{},
  );

  /// Combines [other] into these assets.
  ///
  /// Later plugins win on a name clash, matching the order they are listed in.
  /// There are no clashes between the two VGV plugins today.
  /// Hooks are the exception: they concatenate rather than resolve by name.
  /// Two plugins both registering `PreToolUse` both want to run, so dropping
  /// one would silently disable it.
  PluginAssets merge(PluginAssets other) => PluginAssets(
    skills: _mergeByName(skills, other.skills, (skill) => skill.name),
    agents: _mergeByName(agents, other.agents, (agent) => agent.name),
    mcpServers: {...mcpServers, ...other.mcpServers},
    hooks: [...hooks, ...other.hooks],
  );

  /// Later entries win a name clash, and the result stays sorted by name so
  /// merging cannot lose the ordering [PluginAssetsReader.read] establishes.
  static List<T> _mergeByName<T>(
    List<T> a,
    List<T> b,
    String Function(T) name,
  ) {
    final byName = <String, T>{for (final item in a) name(item): item};
    for (final item in b) {
      byName[name(item)] = item;
    }
    final merged = byName.values.toList()
      ..sort((x, y) => name(x).compareTo(name(y)));
    return merged;
  }
}

/// {@template plugin_assets_reader}
/// Reads the skills, agents and MCP servers out of a plugin directory.
///
/// The two plugins are not internally consistent, so this tolerates the real
/// shapes rather than the documented ones: agents nested in category
/// directories, skills using either `references/` or a flat `reference.md`,
/// and `allowed-tools` separated by spaces in every skill except one.
/// {@endtemplate}
class const PluginAssetsReader() {
  /// Reads every asset under [root].
  ///
  /// Total: a directory with nothing in it yields empty collections rather
  /// than an error. Whether an empty plugin is a problem is the caller's
  /// judgement, because only the caller knows which plugin it asked for.
  PluginAssets read(Directory root) => PluginAssets(
    skills: _readSkills(root.childDirectory('skills')),
    agents: _readAgents(root.childDirectory('agents')),
    mcpServers: _readMcpServers(root.childFile('.mcp.json')),
    hooks: _readHooks(root.childDirectory('hooks')),
  );

  /// Reads `hooks/hooks.json`, whose shape is an event map of registrations:
  /// `{"hooks": {"<Event>": [{"matcher"?, "hooks": [{type, command}]}]}}`.
  ///
  /// Every level is tolerated as absent or the wrong type rather than assumed,
  /// because a plugin may ship no hooks at all.
  List<HookAsset> _readHooks(Directory hooksDir) {
    final file = hooksDir.childFile('hooks.json');
    if (!file.existsSync()) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw PluginParseException(file.path, error.message);
    }

    if (decoded is! Map) {
      throw PluginParseException(file.path, 'expected a JSON object');
    }

    final events = decoded['hooks'];
    if (events is! Map) return const [];

    final assets = <HookAsset>[];
    for (final event in events.entries) {
      final registrations = event.value;
      if (registrations is! List) continue;

      for (final registration in registrations) {
        if (registration is! Map) continue;

        final commands = _readHookCommands(registration['hooks']);
        if (commands.isEmpty) continue;

        final matcher = registration['matcher'];
        assets.add(
          HookAsset(
            event: '${event.key}',
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
    if (raw is! List) return const [];

    final commands = <HookCommand>[];
    for (final entry in raw) {
      if (entry is! Map) continue;

      final command = entry['command'];
      if (command is! String) continue;

      final timeout = entry['timeout'];
      commands.add(
        HookCommand(
          type: entry['type'] is String ? entry['type']! as String : 'command',
          command: command,
          timeout: timeout is int ? timeout : null,
        ),
      );
    }
    return commands;
  }

  List<SkillAsset> _readSkills(Directory skillsDir) {
    if (!skillsDir.existsSync()) return const [];

    final skills = <SkillAsset>[];
    for (final entity in skillsDir.listSync().whereType<Directory>()) {
      final file = entity.childFile('SKILL.md');
      // `skills/shared/` holds references pooled by the other skills and has
      // no SKILL.md of its own. It is not a skill, but it is a link target:
      // 21 reference files across 8 wingspan skills symlink into it, so it
      // must survive any copy that follows.
      if (!file.existsSync()) continue;

      final frontmatter = Frontmatter.parse(
        file.readAsStringSync(),
        path: file.path,
      );
      skills.add(
        SkillAsset(
          name: frontmatter.name ?? p.basename(entity.path),
          frontmatter: frontmatter,
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
          frontmatter: frontmatter,
        ),
      );
    }
    agents.sort((a, b) => a.name.compareTo(b.name));
    return agents;
  }

  Map<String, Map<String, Object?>> _readMcpServers(File mcpFile) {
    if (!mcpFile.existsSync()) return const {};

    final Object? decoded;
    try {
      decoded = jsonDecode(mcpFile.readAsStringSync());
    } on FormatException catch (error) {
      // jsonDecode throws FormatException, which the command runner renders as
      // a CLI usage error.
      throw PluginParseException(mcpFile.path, error.message);
    }

    if (decoded is! Map) {
      throw PluginParseException(mcpFile.path, 'expected a JSON object');
    }

    final servers = decoded['mcpServers'];
    if (servers is! Map) return const {};

    return {
      for (final entry in servers.entries)
        if (entry.value case final Map<Object?, Object?> value)
          '${entry.key}': Map<String, Object?>.from(value),
    };
  }
}
