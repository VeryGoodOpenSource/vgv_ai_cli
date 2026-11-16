/// {@template drift}
/// What of VGV's is gone from a document, and what has been changed, as
/// the dotted key paths or section names VGV wrote.
/// {@endtemplate}
class const Drift({
  /// The key paths, or section names, that the document no longer holds.
  required final List<String> missing,

  /// The key paths, or section names, that hold a different value now.
  required final List<String> drifted,
}) {
  /// {@macro drift}
  this;

  /// Whether nothing is missing and nothing has drifted.
  bool get isEmpty => missing.isEmpty && drifted.isEmpty;
}
