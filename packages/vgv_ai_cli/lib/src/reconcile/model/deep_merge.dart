/// {@template deep_merge}
/// A merged document, what the merge added to it, and whether it kept a
/// value the user set in place of VGV's.
/// {@endtemplate}
class const DeepMerge({
  /// The document with VGV's contribution merged in.
  required final Map<String, dynamic> merged,

  /// Every key the document lacked, and the entries a list gained.
  required final Map<String, dynamic> added,

  /// Whether the merge kept a value the user set in place of VGV's.
  required final bool declined,
}) {
  /// {@macro deep_merge}
  this;
}
