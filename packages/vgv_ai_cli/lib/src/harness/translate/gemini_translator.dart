import 'dart:convert';

import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/format.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template gemini_translator}
/// Configures Gemini CLI.
///
/// Gemini reads `~/.agents/skills` natively. Its agents are markdown with a
/// `name` its loader validates, and its commands are TOML with their own
/// argument placeholder.
/// {@endtemplate}
class const GeminiTranslator() extends HarnessTranslator {
  /// The names Gemini's agent loader accepts.
  ///
  /// Enforced by the loader's own schema, so a name outside it is not loaded
  /// at all.
  static final _validAgentName = RegExp(r'^[a-z0-9_-]+$');

  /// Gemini's argument placeholder. Codex, OpenCode and Pi all keep Claude's
  /// `$ARGUMENTS`, so this substitution belongs to Gemini alone.
  static const _arguments = r'$ARGUMENTS';

  @override
  Harness get harness => Harness.gemini;

  /// The MCP servers, and the instruction file names Gemini loads.
  ///
  /// `AGENTS.md` is listed so Gemini reads the VGV section, and `GEMINI.md`
  /// so naming a second file does not stop it reading its default one.
  @override
  String settings(PluginAssets assets, {required String skillsRoot}) =>
      jsonEncode({
        'mcpServers': {
          for (final server in assets.mcpServers)
            server.name: mcpServerEntry(server),
        },
        'context': {
          'fileName': ['AGENTS.md', 'GEMINI.md'],
        },
      });

  @override
  Map<String, Object?> agent(
    AgentAsset agent, {
    required String instructions,
  }) => {
    'frontmatter': Frontmatter.render({
      'name': agent.name,
      'description': agent.description,
    }),
  };

  /// Gemini's schema is strict: `prompt` is required, `description` optional,
  /// and nothing else is accepted.
  @override
  Map<String, Object?> command(SkillAsset skill) => {
    'toml': TomlDocument.fromMap({
      'description': skill.description,
      'prompt': skill.body.replaceAll(_arguments, '{{args}}'),
    }).toString(),
  };

  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    ...super.notes(assets),
    for (final agent in assets.agents)
      if (!_validAgentName.hasMatch(agent.name))
        TranslationNote(
          subject: 'agent ${agent.name}',
          reason:
              'Gemini only loads agent names matching '
              '${_validAgentName.pattern}, so it will ignore this one',
        ),
  ];
}
