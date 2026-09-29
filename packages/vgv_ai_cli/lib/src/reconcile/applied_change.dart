import 'package:vgv_ai_cli/src/model/planned_change.dart';

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
  ///
  /// The one outcome that both wrote the file and kept a user value.
  partial,

  /// The file was left alone because every difference was the user's:
  /// a value they set, a file of theirs where VGV owns one, or a TOML edit
  /// that would drop their comments. Forcing takes VGV's.
  skipped,

  /// The file was left alone because it could not be parsed. Forcing does
  /// not help, since there is nothing to merge into.
  unparseable,

  /// Reading or writing the file failed.
  failed,

  /// The file already held everything VGV contributes.
  unchanged,
}

/// {@template applied_change}
/// A [PlannedChange] and what applying it did.
/// {@endtemplate}
class AppliedChange {
  /// {@macro applied_change}
  new({required this.change, required this.outcome, this.error});

  /// The change that was applied.
  final PlannedChange change;

  /// What applying [change] did.
  final ChangeOutcome outcome;

  /// Why the change [ChangeOutcome.failed], and null otherwise.
  final String? error;
}
