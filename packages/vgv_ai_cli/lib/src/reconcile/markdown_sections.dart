import 'package:vgv_ai_cli/src/reconcile/line_endings.dart';

/// Opens the section of a markdown file named [name] that VGV manages.
String sectionStart(String name) => '<!-- vgv-ai-cli:$name -->';

/// Closes the section of a markdown file named [name] that VGV manages.
String sectionEnd(String name) => '<!-- /vgv-ai-cli:$name -->';

/// [original] with the section named [name] holding [body].
///
/// An instructions file such as `~/.gemini/AGENTS.md` may already hold the
/// user's own guidance, so everything outside the markers is theirs and is
/// kept, and so is every other section. The section is appended the first
/// time. The file keeps its line endings.
///
/// The section runs from the last start marker that has an end marker after
/// it to the first end marker after that start. So a marker left behind on
/// its own never swallows the user's text and never makes a later run
/// append the section again.
String upsertSection(String original, String name, String body) {
  final (:text, :restore) = normalizeLineEndings(original);
  final section =
      '${sectionStart(name)}\n${body.trimRight()}\n${sectionEnd(name)}';

  return restore(switch (_locate(text, name)) {
    (:final start, :final end) => text.replaceRange(start, end, section),
    null when text.trim().isEmpty => '$section\n',
    null => '${text.trimRight()}\n\n$section\n',
  });
}

/// Where the section named [name] starts and ends in [text], markers
/// included, or null when it has no complete pair of markers.
({int start, int end})? _locate(String text, String name) {
  final close = sectionEnd(name);
  final starts = sectionStart(name).allMatches(text).map((m) => m.start);

  return starts
      .toList()
      .reversed
      .map((start) => (start: start, end: text.indexOf(close, start)))
      .where((pair) => pair.end != -1)
      .map((pair) => (start: pair.start, end: pair.end + close.length))
      .firstOrNull;
}
