import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugins/frontmatter.dart';
import 'package:vgv_ai_cli/src/plugins/models/models.dart';

/// A [Skill] paired with the repo-relative path it was extracted from.
///
/// The `source` path (for example `skills/plan`) is what the materializer
/// copies from and what the lockfile records as the skill's origin.
typedef ExtractedSkill = ({Skill skill, String source});

/// {@template plugin_extractor}
/// Extracts a plugin's MCP servers, skills, and agents from a checked-out
/// repository directory.
///
/// Every method tolerates missing files and malformed entries: an absent source
/// yields an empty result and a single unparseable entry is skipped rather than
/// failing the whole extraction, matching how Claude Code degrades gracefully.
/// {@endtemplate}
class const PluginExtractor() {
  /// Extracts the MCP servers declared in the plugin's `.mcp.json`.
  ///
  /// Returns an empty map when the file is missing or does not carry an
  /// `mcpServers` object.
  Map<String, McpServer> extractMcpServers(Directory pluginDirectory) {
    final file = File(p.join(pluginDirectory.path, '.mcp.json'));
    if (!file.existsSync()) return const {};

    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return const {};
    }
    if (decoded is! Map || decoded['mcpServers'] is! Map) return const {};

    final servers = <String, McpServer>{};
    for (final MapEntry(:key, :value)
        in (decoded['mcpServers'] as Map).entries) {
      if (key is! String || value is! Map) continue;
      servers[key] = McpServer.fromJson(value);
    }
    return servers;
  }

  /// Extracts the skills declared under the plugin's `skills/*/SKILL.md`.
  ///
  /// Each skill directory contributes one entry; directories without a
  /// `SKILL.md` or with frontmatter missing `name`/`description` are skipped.
  List<ExtractedSkill> extractSkills(Directory pluginDirectory) {
    final skillsRoot = Directory(p.join(pluginDirectory.path, 'skills'));
    if (!skillsRoot.existsSync()) return const [];

    final skills = <ExtractedSkill>[];
    final entries = skillsRoot.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final directory in entries) {
      final file = File(p.join(directory.path, 'SKILL.md'));
      if (!file.existsSync()) continue;

      final frontmatter = parseFrontmatter(file.readAsStringSync());
      final name = frontmatter?['name'];
      final description = frontmatter?['description'];
      if (name is! String || description is! String) continue;

      skills.add((
        skill: Skill(name: name, description: description),
        source: p.join('skills', p.basename(directory.path)),
      ));
    }
    return skills;
  }

  /// Extracts the agents declared under the plugin's `agents/**/*.md`.
  ///
  /// The tree is walked recursively; markdown files without frontmatter
  /// carrying both `name` and `description` are skipped.
  List<Agent> extractAgents(Directory pluginDirectory) {
    final agentsRoot = Directory(p.join(pluginDirectory.path, 'agents'));
    if (!agentsRoot.existsSync()) return const [];

    final agents = <Agent>[];
    final files =
        agentsRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.md')
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final frontmatter = parseFrontmatter(file.readAsStringSync());
      final name = frontmatter?['name'];
      final description = frontmatter?['description'];
      if (name is! String || description is! String) continue;

      agents.add(Agent(name: name, description: description));
    }
    return agents;
  }
}
