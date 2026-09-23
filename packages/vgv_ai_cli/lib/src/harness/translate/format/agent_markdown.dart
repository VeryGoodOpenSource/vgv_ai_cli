import 'package:plugin_source/plugin_source.dart';

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
/// Claude Code resolves an agent's `skills:` list itself. No other harness
/// does, so the list becomes an instruction naming the canonical directory.
/// Inlining the skill bodies instead would duplicate content already on disk
/// and grow one agent file more than tenfold.
String renderAgentBody(AgentAsset agent, {required String skillsRoot}) {
  final body = agent.body.trimRight();
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
