import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template change_mode}
/// How a [PlannedChange] lands on a file that may already exist.
///
/// A file VGV owns outright is replaced. A file the user shares with VGV is
/// merged, and each merge keeps the user's own values unless the reconciler
/// is forced.
/// {@endtemplate}
enum ChangeMode {
  /// VGV owns the file and writes it whole.
  own,

  /// Deep merged into a JSON object. Maps merge, lists union, and a scalar
  /// the user already set is kept unless forced.
  mergeJson,

  /// Deep merged into a TOML document with the same rules as [mergeJson].
  ///
  /// New keys are appended as text, so the user's comments and layout
  /// survive. A merge that has to edit what is already there re-serializes
  /// the file, which drops its comments, so it is made only when forced.
  mergeToml,

  /// Written between VGV's markers in a markdown file. Everything outside
  /// the markers belongs to the user and is kept.
  mergeMarkdown,
}

/// {@template planned_change}
/// One file `vgv_ai` intends to write, and how.
/// {@endtemplate}
class PlannedChange {
  /// {@macro planned_change}
  new({
    required this.file,
    required this.contents,
    required this.harness,
    this.mode = ChangeMode.own,
  });

  /// The file to write.
  final File file;

  /// What VGV contributes to [file], before any merge.
  final String contents;

  /// How [contents] lands on [file].
  final ChangeMode mode;

  /// Null when the change is shared rather than owned by one harness.
  final Harness? harness;

  @override
  String toString() {
    final owner = harness?.name ?? 'shared';
    return '[${mode.name}] ($owner) ${file.path}';
  }
}

/// {@template change_outcome}
/// What applying a [PlannedChange] did.
/// {@endtemplate}
enum ChangeOutcome {
  /// The file did not exist and was written.
  created,

  /// The file existed and now holds everything VGV contributes.
  updated,

  /// The file existed and was written, but kept the user's value for at
  /// least one key VGV also sets. Forcing takes VGV's.
  partial,

  /// The file was left alone because it could not be merged safely, or
  /// because every difference was a value the user set.
  skipped,

  /// The file already held everything VGV contributes.
  unchanged,
}

/// {@template applied_change}
/// A [PlannedChange] and what applying it did.
/// {@endtemplate}
class AppliedChange {
  /// {@macro applied_change}
  new({required this.change, required this.outcome});

  /// The change that was applied.
  final PlannedChange change;

  /// What applying [change] did.
  final ChangeOutcome outcome;
}
