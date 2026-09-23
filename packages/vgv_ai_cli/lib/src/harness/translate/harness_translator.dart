import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template harness_translator}
/// Turns the harness-neutral [PluginAssets] into the files one harness reads.
///
/// One implementation per harness, so a new harness is one new class and no
/// edit to an existing one. Implementations depend on the neutral model and on
/// [PlannedChange]; none depends on another translator.
/// {@endtemplate}
abstract class HarnessTranslator {
  /// {@macro harness_translator}
  const new();

  /// Which harness this configures.
  Harness get harness;

  /// The changes that configure this harness, plus anything it could not
  /// express.
  ///
  /// Returns changes rather than applying them, so `--check` is a true dry run
  /// and the merge and backup rules stay in the reconcile layer.
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  });

  /// The brick fragment rendered at [path].
  ///
  /// Appends a [TranslationNote] and returns null when the brick rendered no
  /// such file, which means this harness was not selected when it ran. Each
  /// translator wraps the result in the [PlannedChange] its own format needs,
  /// so this stays one branch rather than a switch over every mode.
  String? stagedContents({
    required StagedOutput staged,
    required String path,
    required File target,
    required List<TranslationNote> notes,
  }) {
    final contents = staged[path];
    if (contents != null) return contents;

    notes.add(
      TranslationNote(
        subject: path,
        reason:
            'the agents brick rendered no such file, so ${target.path} was '
            'left alone',
      ),
    );
    return null;
  }
}
