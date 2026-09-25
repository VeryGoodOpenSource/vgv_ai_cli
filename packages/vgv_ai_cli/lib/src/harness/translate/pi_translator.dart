import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template pi_translator}
/// Configures Pi.
///
/// Pi reads `~/.agents/skills` natively. It is minimal by design, with no
/// subagents, no MCP and no declarative hooks, so it gets its settings and its
/// prompts and nothing that would imitate the rest.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.pi;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = p.join(home.path, '.pi', 'agent');
    final fs = home.fileSystem;
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    final settings = stagedContents(
      staged: staged,
      fragment: StagedFragment.piSettings,
      target: fs.file(p.join(root, 'settings.json')),
      notes: notes,
    );
    if (settings != null) {
      changes.add(
        PlannedChange.mergeJson(
          file: fs.file(p.join(root, 'settings.json')),
          contents: settings,
          harness: harness,
        ),
      );
    }

    for (final skill in assets.invocableSkills) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'prompts', '${skill.name}.md')),
          contents: skill.body,
          harness: harness,
        ),
      );
    }

    return TranslationResult(
      changes: changes,
      notes: [...notes, ...hooksNotes(assets)],
    );
  }
}
