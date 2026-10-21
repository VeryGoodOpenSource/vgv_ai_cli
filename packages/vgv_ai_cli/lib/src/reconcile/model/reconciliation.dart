import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/model/applied_change.dart';

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
}) {
  /// {@macro reconciliation}
  this;
}
