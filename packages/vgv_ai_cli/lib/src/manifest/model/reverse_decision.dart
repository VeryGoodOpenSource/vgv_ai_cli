import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template reverse_decision}
/// What reversing an entry leaves in its file, and whether any of what VGV
/// wrote was kept.
/// {@endtemplate}
class const ReverseDecision({
  /// What the file holds once the entry is reversed, or null to delete it.
  required final List<int>? bytes,

  /// Whether any of what VGV wrote was kept, because the user changed it.
  required final bool kept,

  /// What the manifest still records of the entry once it is partly
  /// reversed, or null when the rest is the user's.
  final ManifestEntry? retained,

  /// Whether deleting the file also deletes what a symlink there links to.
  ///
  /// Only a file that is still VGV's is deleted through a link, so forcing
  /// cannot reach a file the user put at the other end.
  final bool throughLink = true,
});
