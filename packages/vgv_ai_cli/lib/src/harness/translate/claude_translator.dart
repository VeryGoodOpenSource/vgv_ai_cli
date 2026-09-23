import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template claude_translator}
/// Configures Claude Code, which needs no assets translated.
///
/// Claude Code is the one harness that installs the plugins natively, so this
/// plans the marketplace wiring and nothing else. Copying the skills and agents
/// here as well would duplicate what the plugin system already does, and the
/// two copies would drift apart on the next plugin release.
/// {@endtemplate}
class const ClaudeTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.claude;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final notes = <TranslationNote>[];
    final target = home.fileSystem.file(
      p.join(home.path, '.claude', 'settings.json'),
    );
    final settings = stagedContents(
      staged: staged,
      path: StagedPaths.claudeSettings,
      target: target,
      notes: notes,
    );

    return TranslationResult(
      changes: [
        if (settings != null)
          PlannedChange.mergeJson(
            file: target,
            contents: settings,
            harness: harness,
          ),
      ],
      notes: notes,
    );
  }
}
