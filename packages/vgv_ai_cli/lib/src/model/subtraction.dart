/// {@template subtraction}
/// A document with VGV's contribution taken out of it.
/// {@endtemplate}
class const Subtraction({
  /// What is left of the document.
  required final Map<String, dynamic> remaining,

  /// Whether any of what VGV wrote was kept, because the user changed it.
  required final bool kept,
}) {
  /// {@macro subtraction}
  this;
}
