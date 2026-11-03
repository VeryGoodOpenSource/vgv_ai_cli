import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/format/format.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';
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

  /// [agent] for every harness: the shared instructions, pointing at the
  /// shared skills, and each translator's fields, pointing at the copy of
  /// the skills and plugin files its harness reads.
  Map<String, Object?> _agent(AgentAsset agent) {
    final shared = agentsSkillsRoot(home);
    return {
      'name': agent.name,
      'instructions': agentInstructions(
        agent.withBody(_expand(agent.body, skillsRoot: shared)),
        skillsRoot: shared.path,
      ),
      for (final translator in translators)
        translator.harness.name: _agentFields(translator, agent).toMap(),
    };
  }

  /// What [translator] renders [agent] with, pointing at the copy of the
  /// skills and plugin files its harness reads.
  HarnessFields _agentFields(HarnessTranslator translator, AgentAsset agent) {
    final skillsRoot = _skillsRootOf(translator);
    final rooted = agent.withBody(_expand(agent.body, skillsRoot: skillsRoot));
    return translator.agent(
      rooted,
      instructions: agentInstructions(rooted, skillsRoot: skillsRoot.path),
    );
  }

  /// [skill] as a command for every harness, pointing at the plugin files
  /// beside the copy of the skills each one reads.
  Map<String, Object?> _command(SkillAsset skill) => {
    'name': skill.name,
    'body': _expand(skill.body, skillsRoot: agentsSkillsRoot(home)),
    for (final translator in translators)
      translator.harness.name: translator
          .command(
            skill.withBody(
              _expand(skill.body, skillsRoot: _skillsRootOf(translator)),
            ),
          )
          .toMap(),
  };

  /// The copy of the skills [translator]'s harness reads: its own, or the
  /// shared one.
  Directory _skillsRootOf(HarnessTranslator translator) =>
      translator.skillsRoot(home) ?? agentsSkillsRoot(home);

  /// [text] with the plugin files it names spelled out as their copy beside
  /// [skillsRoot].
  static String _expand(String text, {required Directory skillsRoot}) =>
      expandPluginFiles(text, filesRoot: pluginFilesRoot(skillsRoot));

  static Map<String, String> _entry(String name, String description) => {
    'name': name,
    'description': description,
  };
}
