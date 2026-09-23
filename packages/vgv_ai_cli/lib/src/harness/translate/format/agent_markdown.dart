import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_tool_map.dart';

/// Renders an agent for a harness that reads markdown with frontmatter.
///
/// [frontmatter] is whatever that harness requires; the body and the skills
/// pointer are the same everywhere.
String renderAgent(
  AgentAsset agent,
  Map<String, Object?> frontmatter, {
  required String skillsRoot,
}) =>
    '${Frontmatter.render(frontmatter)}\n'
    '${renderAgentBody(agent, skillsRoot: skillsRoot)}';

/// Renders an agent's instructions, with its skills restated as a pointer.
///
/// MCP tool names are rewritten here as well as in the shared skills copy.
/// Every harness gets its own copy of an agent, and Pi supports no MCP at all,
/// so leaving the raw `mcp__*` names in would hand Pi an instruction naming a
/// tool it cannot invoke. `SkillsTranslator` owns reporting anything unmapped,
/// so this rewrites without duplicating the note.
///
/// Claude Code resolves an agent's `skills:` list itself. No other harness
/// does, so the list becomes an instruction naming the canonical directory.
/// Inlining the skill bodies instead would duplicate content already on disk
/// and grow one agent file more than tenfold.
String renderAgentBody(AgentAsset agent, {required String skillsRoot}) {
  final body = McpToolMap.rewrite(agent.body).trimRight();
  if (agent.skills.isEmpty) return '$body\n';

  final list = [for (final skill in agent.skills) '- `$skill`'].join('\n');
  return '$body\n'
      '\n'
      '## Required skills\n'
      '\n'
      'Load these skills from `$skillsRoot` before you start. They are part '
      'of your instructions, not optional reading.\n'
      '\n'
      '$list\n';
}
