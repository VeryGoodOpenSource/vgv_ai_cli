import 'package:vgv_ai_cli/src/reconcile/model/held_back.dart';

/// {@template write_decision}
/// The bytes a change leaves in its file, and what it held back.
/// {@endtemplate}
class const WriteDecision({
  /// What the file holds once the change is applied.
  required final List<int> bytes,

  /// What the change kept of the user's instead of taking VGV's.
  required final HeldBack held,
});
