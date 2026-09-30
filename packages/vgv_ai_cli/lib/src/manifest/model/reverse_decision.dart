/// {@template reverse_decision}
/// What reversing an entry leaves in its file, and whether any of what VGV
/// wrote was kept.
/// {@endtemplate}
class const ReverseDecision({
  /// What the file holds once the entry is reversed, or null to delete it.
  required final List<int>? bytes,

  /// Whether any of what VGV wrote was kept, because the user changed it.
  required final bool kept,
});
