import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/format.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template gemini_translator}
/// Configures Gemini CLI.
///
/// Gemini reads `~/.agents/skills` natively, so the work here is its two other
/// formats: agents are markdown in a flat directory, and commands are TOML with
/// their own argument placeholder.
/// {@endtemplate}
class const GeminiTranslator() extends HarnessTranslator {
  /// The names Gemini's agent loader accepts.
  ///
  /// Enforced by the loader's own schema, so a name outside it is not loaded
  /// at all. Validated here rather than written and silently ignored.
  static final _validAgentName = RegExp(r'^[a-z0-9_-]+$');

  /// Gemini's argument placeholder. Codex, OpenCode and Pi all keep Claude's
  /// `$ARGUMENTS`, so this substitution belongs to Gemini alone.
  static const _arguments = r'$ARGUMENTS';

  @override
  Harness get harness => Harness.gemini;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = p.join(home.path, '.gemini');
    final fs = home.fileSystem;
    final skillsRoot = agentsSkillsRoot(home).path;
    final settingsFile = fs.file(p.join(root, 'settings.json'));
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    final settings = stagedContents(
      staged: staged,
      fragment: StagedFragment.geminiSettings,
      target: settingsFile,
      notes: notes,
    );
    if (settings != null) {
      changes.add(
        PlannedChange.mergeJson(
          file: settingsFile,
          contents: settings,
          harness: harness,
        ),
      );
    }

    // Flat: the loader does not scan subdirectories, so wingspan's category
    // directories are flattened away here.
    for (final agent in assets.agents) {
      if (!_validAgentName.hasMatch(agent.name)) {
        notes.add(
          TranslationNote(
            subject: 'agent ${agent.name}',
            reason:
                'Gemini only loads agent names matching '
                '${_validAgentName.pattern}, so this one would be ignored',
          ),
        );
        continue;
      }

      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'agents', '${agent.name}.md')),
          contents: renderAgent(agent, {
            'name': agent.name,
            'description': agent.description,
          }, skillsRoot: skillsRoot),
          harness: harness,
        ),
      );
    }

    for (final skill in assets.invocableSkills) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'commands', '${skill.name}.toml')),
          contents: _command(skill),
          harness: harness,
        ),
      );
    }

    final hooks = buildHookDocument(
      assets.hooks,
      home: home,
      vocabulary: HookVocabulary.gemini,
      notes: notes,
    );
    if (hooks.isNotEmpty) {
      changes.add(
        PlannedChange.mergeJson(
          file: settingsFile,
          contents: jsonEncode({'hooks': hooks}),
          harness: harness,
        ),
      );
    }

    return TranslationResult(changes: changes, notes: notes);
  }

  /// Renders a command. Gemini's schema is strict: `prompt` is required,
  /// `description` optional, and nothing else is accepted.
  String _command(SkillAsset skill) => TomlDocument.fromMap({
    'description': skill.description,
    'prompt': McpToolMap.rewrite(skill.body).replaceAll(_arguments, '{{args}}'),
  }).toString();
}
