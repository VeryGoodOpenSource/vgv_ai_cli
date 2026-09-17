import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugin_source/frontmatter.dart';

/// Frontmatter keys Claude Code understands that no other harness does.
///
/// Packaging a skill with these breaks it elsewhere, so they are dropped when
/// a skill is written to the canonical location.
const claudeOnlyKeys = <String>{
  'user-invocable',
  'disable-model-invocation',
  'effort',
  'when_to_use',
  'context',
  'paths',
  'shell',
  'agent',
};

/// {@template skill_asset}
/// A skill resolved from a plugin.
/// {@endtemplate}
class SkillAsset {
  /// {@macro skill_asset}
  const new({
    required this.name,
    required this.frontmatter,
    required this.body,
    required this.directory,
    required this.userInvocable,
  });

  /// The skill name, taken from frontmatter and falling back to the directory.
  final String name;

  /// Parsed frontmatter, still including any Claude-only keys.
  final Map<String, String> frontmatter;

  /// The markdown body, without frontmatter.
  final String body;

  /// Where the skill was resolved from, so `references/` and `scripts/` can be
  /// copied alongside it.
  final Directory directory;

  /// Whether the skill is meant to be invoked as a command.
  ///
  /// The Flutter plugin omits `user-invocable` entirely yet its skills are
  /// invocable, so an absent key means `true`.
  final bool userInvocable;

  /// A one-line description for an index table.
  String get description =>
      frontmatter['description']?.replaceAll('\n', ' ').trim() ?? '';

  /// Frontmatter safe to write for a non-Claude harness.
  Map<String, String> get portableFrontmatter {
    return {
      for (final MapEntry(:key, :value) in frontmatter.entries)
        if (!claudeOnlyKeys.contains(key)) key: value,
    };
  }
}

/// {@template agent_asset}
/// A subagent resolved from a plugin.
/// {@endtemplate}
class AgentAsset {
  /// {@macro agent_asset}
  const new({
    required this.name,
    required this.frontmatter,
    required this.body,
    required this.skills,
  });

  /// The agent name.
  final String name;

  /// Parsed frontmatter.
  final Map<String, String> frontmatter;

  /// The agent prompt.
  final String body;

  /// Skills the agent expects to have loaded.
  ///
  /// Claude Code resolves these itself. Every other harness needs them inlined
  /// into the agent body at install time.
  final List<String> skills;

  /// A one-line description for an index table.
  String get description =>
      frontmatter['description']?.replaceAll('\n', ' ').trim() ?? '';
}

/// {@template plugin_assets}
/// Everything one or more plugins contribute, in a harness-neutral shape.
/// {@endtemplate}
class PluginAssets {
  /// {@macro plugin_assets}
  const new({
    required this.skills,
    required this.agents,
    required this.mcpServers,
  });

  /// An empty set of assets.
  static const empty = PluginAssets(
    skills: [],
    agents: [],
    mcpServers: <String, Map<String, dynamic>>{},
  );

  /// Resolved skills.
  final List<SkillAsset> skills;

  /// Resolved subagents.
  final List<AgentAsset> agents;

  /// MCP servers declared across the plugins, keyed by server name.
  final Map<String, Map<String, dynamic>> mcpServers;

  /// Combines [other] into these assets.
  ///
  /// Later plugins win on a name clash, matching the order they are listed in.
  PluginAssets merge(PluginAssets other) {
    return PluginAssets(
      skills: _mergeByName(skills, other.skills, (s) => s.name),
      agents: _mergeByName(agents, other.agents, (a) => a.name),
      mcpServers: {...mcpServers, ...other.mcpServers},
    );
  }

  static List<T> _mergeByName<T>(
    List<T> a,
    List<T> b,
    String Function(T) name,
  ) {
    final byName = <String, T>{for (final item in a) name(item): item};
    for (final item in b) {
      byName[name(item)] = item;
    }
    return byName.values.toList();
  }
}

/// Reads the skills, agents and MCP servers out of a plugin directory.
///
/// The two plugins are not internally consistent, so this tolerates the real
/// shapes rather than the documented ones: agents nested in category
/// directories, skills using either `references/` or a flat `reference.md`,
/// and `allowed-tools` separated by spaces in every skill except one.
class PluginAssetsReader {
  /// Reads every asset under [root].
  PluginAssets read(Directory root) {
    return PluginAssets(
      skills: _readSkills(Directory(p.join(root.path, 'skills'))),
      agents: _readAgents(Directory(p.join(root.path, 'agents'))),
      mcpServers: _readMcpServers(File(p.join(root.path, '.mcp.json'))),
    );
  }

  List<SkillAsset> _readSkills(Directory skillsDir) {
    if (!skillsDir.existsSync()) return [];
    final skills = <SkillAsset>[];
    for (final entity in skillsDir.listSync().whereType<Directory>()) {
      final skillFile = File(p.join(entity.path, 'SKILL.md'));
      // `skills/shared/` holds references pooled by the other skills and has
      // no SKILL.md of its own.
      if (!skillFile.existsSync()) continue;

      final document = Frontmatter.parse(skillFile.readAsStringSync());
      final invocable = document.frontmatter['user-invocable'];
      skills.add(
        SkillAsset(
          name: document.frontmatter['name'] ?? p.basename(entity.path),
          frontmatter: document.frontmatter,
          body: document.body,
          directory: entity,
          userInvocable: invocable != 'false',
        ),
      );
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  List<AgentAsset> _readAgents(Directory agentsDir) {
    if (!agentsDir.existsSync()) return [];
    final agents = <AgentAsset>[];
    // Wingspan nests agents under a category directory; the Flutter plugin
    // does not. Every other harness expects them flat, so recurse and flatten.
    for (final file in agentsDir.listSync(recursive: true).whereType<File>()) {
      if (p.extension(file.path) != '.md') continue;
      final document = Frontmatter.parse(file.readAsStringSync());
      agents.add(
        AgentAsset(
          name:
              document.frontmatter['name'] ??
              p.basenameWithoutExtension(file.path),
          frontmatter: document.frontmatter,
          body: document.body,
          skills: _parseList(document.frontmatter['skills']),
        ),
      );
    }
    agents.sort((a, b) => a.name.compareTo(b.name));
    return agents;
  }

  Map<String, Map<String, dynamic>> _readMcpServers(File mcpFile) {
    if (!mcpFile.existsSync()) return {};
    final decoded = jsonDecode(mcpFile.readAsStringSync());
    if (decoded is! Map) return {};
    final servers = decoded['mcpServers'];
    if (servers is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in servers.entries)
        if (value is Map) '$key': Map<String, dynamic>.from(value),
    };
  }

  /// Parses both `[a, b]` and a YAML block sequence.
  static List<String> _parseList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final value = raw.trim();
    if (value.startsWith('[')) {
      return value
          .substring(1, value.endsWith(']') ? value.length - 1 : value.length)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- '))
        .map((line) => line.substring(2).trim())
        .toList();
  }
}
