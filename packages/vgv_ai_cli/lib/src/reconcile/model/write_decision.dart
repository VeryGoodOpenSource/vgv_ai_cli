import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/model/held_back.dart';

/// {@template write_decision}
/// The bytes a change leaves in its file, what it held back, and what the
/// manifest should say about the file.
/// {@endtemplate}
class const WriteDecision({
  /// What the file holds once the change is applied.
  required final List<int> bytes,

  /// What the change kept of the user's instead of taking VGV's.
  required final HeldBack held,

  /// What the manifest records for the file. Null leaves the manifest's
  /// entry as it is, and an empty contribution drops it, since nothing in
  /// the file is VGV's.
  final ManifestEntry? entry,
});
