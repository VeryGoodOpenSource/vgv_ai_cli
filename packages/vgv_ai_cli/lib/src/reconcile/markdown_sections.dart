/// Opens the section of a markdown file named [name] that VGV manages.
String sectionStart(String name) => '<!-- vgv-ai-cli:$name -->';

/// Closes the section of a markdown file named [name] that VGV manages.
String sectionEnd(String name) => '<!-- /vgv-ai-cli:$name -->';

/// [text] with the section named [name] holding [body].
///
/// An instructions file such as `~/.gemini/AGENTS.md` may already hold the
/// user's own guidance, so everything outside the markers is theirs and is
/// kept, and so is every other section. The section is appended the first
/// time.
///
/// The last end marker is paired with the start marker nearest before it,
/// so a marker left behind on its own never swallows the user's text and
/// never makes a later run append the section again.
String upsertSection(String text, String name, String body) {
  final section =
      '${sectionStart(name)}\n${body.trimRight()}\n${sectionEnd(name)}';

  return switch (_locate(text, name)) {
    (:final start, :final end) => text.replaceRange(start, end, section),
    null when text.trim().isEmpty => '$section\n',
    null => '${text.trimRight()}\n\n$section\n',
  };
}

/// Where the section named [name] starts and ends in [text], markers
/// included, or null when it has no complete pair of markers.
({int start, int end})? _locate(String text, String name) {
  final end = text.lastIndexOf(sectionEnd(name));
  if (end == -1) return null;

  final start = text.lastIndexOf(sectionStart(name), end);
  if (start == -1) return null;

  return (start: start, end: end + sectionEnd(name).length);
}
