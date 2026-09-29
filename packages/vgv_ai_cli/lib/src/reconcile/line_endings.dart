/// [original] with every `\r\n` made `\n`, so an edit only ever deals in
/// `\n`, and `restore`, which turns an edit of that text back into
/// [original]'s line endings.
({String text, String Function(String edit) restore}) normalizeLineEndings(
  String original,
) {
  final ending = original.contains('\r\n') ? '\r\n' : '\n';
  return (
    text: original.replaceAll('\r\n', '\n'),
    restore: (edit) => edit.replaceAll('\n', ending),
  );
}
