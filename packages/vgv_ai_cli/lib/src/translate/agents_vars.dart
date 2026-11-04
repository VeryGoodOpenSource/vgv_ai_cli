import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

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

  /// The user's home directory, which holds the shared skills and each
  /// harness's own copy.
  required final Directory home,

  /// The hooks fragment of each harness that has one.
  final Map<Harness, String> hooks = const {},
}) {
  /// {@macro agents_vars}
  this;

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

  /// [agent] for every harness, each pointing at the skills and plugin
  /// files that harness reads: the shared instructions, and the fields of
  /// every translator whose harness reads a copy.
  Map<String, Object?> _agent(AgentAsset agent) => {
    'name': agent.name,
    'instructions': _instructions(agent, agentsSkillsRoot(home)),
    for (final translator in translators)
      if (translator.readSkillsRoot(home) case final skillsRoot?)
        translator.harness.name: translator
            .agent(
              _rooted(agent, skillsRoot),
              instructions: _instructions(agent, skillsRoot),
            )
            .toMap(),
  };

  /// [skill] as a command for every harness, pointing at the plugin files
  /// that harness reads.
  Map<String, Object?> _command(SkillAsset skill) => {
    'name': skill.name,
    'body': expandPluginFiles(skill.body, skillsRoot: agentsSkillsRoot(home)),
    for (final translator in translators)
      if (translator.readSkillsRoot(home) case final skillsRoot?)
        translator.harness.name: translator
            .command(
              skill.withBody(
                expandPluginFiles(skill.body, skillsRoot: skillsRoot),
              ),
            )
            .toMap(),
  };

  /// [agent]'s instructions for a harness that reads the skills under
  /// [skillsRoot].
  static String _instructions(AgentAsset agent, Directory skillsRoot) =>
      agentInstructions(
        _rooted(agent, skillsRoot),
        skillsRoot: skillsRoot.path,
      );

  /// [agent] pointing at the plugin files beside [skillsRoot].
  static AgentAsset _rooted(AgentAsset agent, Directory skillsRoot) =>
      agent.withBody(expandPluginFiles(agent.body, skillsRoot: skillsRoot));

  static Map<String, String> _entry(String name, String description) => {
    'name': name,
    'description': description,
  };
}
