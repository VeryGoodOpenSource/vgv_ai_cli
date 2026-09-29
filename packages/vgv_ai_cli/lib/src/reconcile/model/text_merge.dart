import 'package:vgv_ai_cli/src/reconcile/model/held_back.dart';

/// {@template text_merge}
/// The text a merge leaves in its file, and what it held back.
/// {@endtemplate}
class const TextMerge({
  /// What the file holds once the merge is applied.
  required final String contents,

  /// What the merge kept of the user's instead of taking VGV's.
  required final HeldBack held,
});
