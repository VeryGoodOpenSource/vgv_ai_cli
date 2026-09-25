import 'package:plugin_source/plugin_source.dart';

/// An agent's instructions, with its skills restated as a pointer.
///
/// Claude Code resolves an agent's `skills:` list itself. No other harness
/// does, so the list becomes an instruction naming the canonical directory.
/// Inlining the skill bodies instead would duplicate content already on disk
/// and grow one agent file more than tenfold.
///
/// Rendered here rather than in a brick partial because Codex embeds the same
/// text in TOML, which mustache cannot escape. One renderer keeps one wording.
String agentInstructions(AgentAsset agent, {required String skillsRoot}) {
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
