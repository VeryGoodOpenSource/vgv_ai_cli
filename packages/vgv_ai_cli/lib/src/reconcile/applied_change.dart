import 'package:vgv_ai_cli/src/model/manifest/install_manifest.dart';
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
  /// least one key VGV also sets. The only outcome that both writes the file
  /// and keeps a user value. Forcing takes VGV's.
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

/// {@template reconciliation}
/// What applying a plan did, change by change, and the manifest that
/// records what VGV owns afterwards.
/// {@endtemplate}
class const Reconciliation({
  /// Each change that was applied, and what applying it did.
  required final List<AppliedChange> changes,

  /// The manifest the changes were applied against, updated with what they
  /// wrote. On a dry run it records what they would have written.
  required final InstallManifest manifest,
});
