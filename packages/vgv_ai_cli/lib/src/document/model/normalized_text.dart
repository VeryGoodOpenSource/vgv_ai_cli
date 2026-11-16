/// {@template normalized_text}
/// Text with every `\r\n` made `\n`, so an edit only ever deals in `\n`, and
/// the [ending] of the text it came from.
/// {@endtemplate}
class const NormalizedText({
  /// The text, with `\n` line endings only.
  required final String text,

  /// The line ending of the text [text] was normalized from.
  required final String ending,
}) {
  /// {@macro normalized_text}
  this;

  /// {@macro normalized_text}
  ///
  /// Normalizes [original], so an edit of it can be turned back into
  /// [original]'s line endings.
  new from(String original)
    : this(
        text: original.replaceAll('\r\n', '\n'),
        ending: original.contains('\r\n') ? '\r\n' : '\n',
      );

  /// [edit], an edit of [text], with [ending] line endings.
  String restore(String edit) => edit.replaceAll('\n', ending);
}
