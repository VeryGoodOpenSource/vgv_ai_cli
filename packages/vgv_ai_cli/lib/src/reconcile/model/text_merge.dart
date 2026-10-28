import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/model/held_back.dart';

/// {@template text_merge}
/// The text a merge leaves in its file, what it held back, and what of it
/// is VGV's.
/// {@endtemplate}
class const TextMerge({
  /// What the file holds once the merge is applied.
  required final String contents,

  /// What the merge kept of the user's instead of taking VGV's.
  required final HeldBack held,

  /// What of [contents] VGV contributed, and null when nothing could be
  /// parsed.
  final Contribution? contribution,
}) {
  /// {@macro text_merge}
  this;
}
