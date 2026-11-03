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
    final rooted = _rootedAgent(agent, skillsRoot: shared);
    return {
      'name': agent.name,
      'instructions': agentInstructions(rooted, skillsRoot: shared.path),
      for (final translator in translators)
        translator.harness.name: _agentFields(
          translator,
          agent,
          skillsRoot: translator.skillsRoot(home) ?? shared,
        ).toMap(),
    };
  }

  /// What [translator] renders [agent] with, its skills read from
  /// [skillsRoot].
  static HarnessFields _agentFields(
    HarnessTranslator translator,
    AgentAsset agent, {
    required Directory skillsRoot,
  }) {
    final rooted = _rootedAgent(agent, skillsRoot: skillsRoot);
    return translator.agent(
      rooted,
      instructions: agentInstructions(rooted, skillsRoot: skillsRoot.path),
    );
  }

  /// [skill] as a command for every harness, pointing at the plugin files
  /// beside the copy of the skills each one reads.
  Map<String, Object?> _command(SkillAsset skill) {
    final shared = agentsSkillsRoot(home);
    return {
      'name': skill.name,
      'body': _rootedSkill(skill, skillsRoot: shared).body,
      for (final translator in translators)
        translator.harness.name: translator
            .command(
              _rootedSkill(
                skill,
                skillsRoot: translator.skillsRoot(home) ?? shared,
              ),
            )
            .toMap(),
    };
  }

  /// [agent] with the plugin root its body names spelled out as the copy
  /// beside [skillsRoot].
  static AgentAsset _rootedAgent(
    AgentAsset agent, {
    required Directory skillsRoot,
  }) => AgentAsset(
    name: agent.name,
    description: agent.description,
    body: _expand(agent.body, plugin: agent.plugin, skillsRoot: skillsRoot),
    skills: agent.skills,
    plugin: agent.plugin,
  );

  /// [skill] with the plugin root its body names spelled out as the copy
  /// beside [skillsRoot].
  static SkillAsset _rootedSkill(
    SkillAsset skill, {
    required Directory skillsRoot,
  }) => SkillAsset(
    name: skill.name,
    description: skill.description,
    body: _expand(skill.body, plugin: skill.plugin, skillsRoot: skillsRoot),
    userInvocable: skill.userInvocable,
    allowedTools: skill.allowedTools,
    portableFrontmatter: skill.portableFrontmatter,
    directory: skill.directory,
    plugin: skill.plugin,
  );

  /// [text] with [plugin]'s root spelled out as its copy beside
  /// [skillsRoot].
  static String _expand(
    String text, {
    required String? plugin,
    required Directory skillsRoot,
  }) => expandPluginRoot(
    text,
    plugin: plugin,
    filesRoot: pluginFilesRoot(skillsRoot),
  );

  static Map<String, String> _entry(String name, String description) => {
    'name': name,
    'description': description,
  };
}
