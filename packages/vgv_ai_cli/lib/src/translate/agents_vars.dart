import 'package:file/file.dart';
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

  /// The directory every harness is configured under.
  required final Directory home,
}) {
  /// The vars, keyed as the brick reads them.
  ///
  /// `agents` and `commands` are the only top-level lists, and an empty one
  /// is left out rather than passed through as `[]`. A brick file path loops
  /// over a list to decide how many files to render, and an empty list still
  /// renders one file, with nothing where its name should be: a stray `.md`
  /// in the user's config directory.
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
      for (final translator in translators)
        '${translator.harness.name}_hooks': ?translator.hooks(
          assets,
          hooksRoot: harnessHooksRoot(translator.harness.configDirectory(home)),
        ),
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
    final instructions = agentInstructions(
      agent,
      skillsRoot: agentsSkillsRoot(home).path,
    );
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
