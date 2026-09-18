import 'package:vgv_ai_cli/src/generation/harness_selection.dart';
import 'package:vgv_ai_cli/src/generation/skill_target.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

/// Builds the `agents` brick vars from resolved plugins.
///
/// Each skill is given its canonical [skillsRoot] path so every harness can
/// reference the single materialized copy. MCP servers and agents are flattened
/// across all plugins; on an MCP server name collision the last plugin wins,
/// matching [ResolvedPlugins.mcpServers].
Map<String, dynamic> buildAgentsVars({
  required ResolvedPlugins plugins,
  required HarnessSelection harnesses,
  required String skillsRoot,
}) {
  final skills = <Map<String, dynamic>>[
    for (final plugin in plugins.plugins)
      for (final entry in plugin.skills)
        entry.skill
            .withPath(
              skillCanonicalPath(
                skillsRoot: skillsRoot,
                plugin: plugin.name,
                source: entry.source,
              ),
            )
            .toVars(),
  ];

  return <String, dynamic>{
    ...harnesses.toVars(),
    'skills_root': skillsRoot,
    'skills': skills,
    'agents': [for (final agent in plugins.agents) agent.toVars()],
    'mcp_servers': <String, dynamic>{
      for (final MapEntry(:key, :value) in plugins.mcpServers.entries)
        key: value.toVars(),
    },
  };
}
