import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/format.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template agents_vars}
/// The vars the `agents` brick renders against.
///
/// Every value is finished: the brick only chooses where each one goes.
/// {@endtemplate}
class const AgentsVars({
  /// The translators of the harnesses being configured.
  required final List<HarnessTranslator> translators,

  /// What the plugins contribute.
  required final PluginAssets assets,

  /// Where the shared skills are written.
  required final String skillsRoot,
}) {
  /// The vars, keyed as the brick reads them.
  ///
  /// `agents` and `commands` are the only top-level lists, and each is left
  /// out when empty. Mason renders a path loop once for every combination of
  /// every top-level list, and renders an empty one as a file with no name.
  Map<String, Object?> toMap() {
    final agents = [for (final agent in assets.agents) _agent(agent)];
    final commands = [
      for (final skill in assets.invocableSkills) _command(skill),
    ];

    return {
      for (final harness in Harness.values)
        harness.name: translators.any((t) => t.harness == harness),
      for (final translator in translators)
        '${translator.harness.name}_settings': ?translator.settings(assets),
      if (agents.isNotEmpty) 'agents': agents,
      if (commands.isNotEmpty) 'commands': commands,
      'index': {
        'has_skills': assets.skills.isNotEmpty,
        'skills': [
          for (final skill in assets.skills)
            _entry(skill.name, skill.description),
        ],
        'has_agents': assets.agents.isNotEmpty,
        'agents': [
          for (final agent in assets.agents)
            _entry(agent.name, agent.description),
        ],
      },
    };
  }

  Map<String, Object?> _agent(AgentAsset agent) {
    final instructions = agentInstructions(agent, skillsRoot: skillsRoot);
    return {
      'name': agent.name,
      'instructions': instructions,
      for (final translator in translators)
        translator.harness.name: translator
            .agent(agent, instructions: instructions)
            .toMap(),
    };
  }

  Map<String, Object?> _command(SkillAsset skill) => {
    'name': skill.name,
    'body': skill.body,
    for (final translator in translators)
      translator.harness.name: translator.command(skill).toMap(),
  };

  static Map<String, String> _entry(String name, String description) => {
    'name': name,
    'description': description,
  };
}
