import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';

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

  /// The hooks fragment of each harness that has one.
  final Map<Harness, String> hooks = const {},
}) {
  /// The vars, keyed as the brick reads them.
  ///
  /// `agents` and `commands` are left out when empty: the brick loops a file
  /// path over each, and an empty list still renders one nameless file.
  Map<String, Object?> toMap() {
    final agents = [for (final agent in assets.agents) _agent(agent)];
    final commands = [
      for (final skill in assets.invocableSkills) _command(skill),
    ];

    return {
      for (final harness in Harness.values)
        harness.name: translators.any((t) => t.harness == harness),
      for (final translator in translators) ...{
        '${translator.harness.name}_settings': ?translator.settings(assets),
        '${translator.harness.name}_hooks': ?hooks[translator.harness],
      },
      if (agents.isNotEmpty) 'agents': agents,
      if (commands.isNotEmpty) 'commands': commands,
      'index': _index(),
    };
  }

  /// What `AGENTS.md` lists.
  Map<String, Object?> _index() => {
    'has_skills': assets.skills.isNotEmpty,
    'skills': [
      for (final skill in assets.skills) _entry(skill.name, skill.description),
    ],
    'has_agents': assets.agents.isNotEmpty,
    'agents': [
      for (final agent in assets.agents) _entry(agent.name, agent.description),
    ],
  };

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
