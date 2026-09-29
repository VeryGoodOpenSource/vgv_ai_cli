import 'package:vgv_ai_cli/src/reconcile/model/model.dart';

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
  final NormalizedText(:text, :restore) = NormalizedText.from(original);
  final section =
      '${sectionStart(name)}\n${body.trimRight()}\n${sectionEnd(name)}';

  return restore(switch (_locate(text, name)) {
    SectionSpan(:final start, :final end) => text.replaceRange(
      start,
      end,
      section,
    ),
    null when text.trim().isEmpty => '$section\n',
    null => '${text.trimRight()}\n\n$section\n',
  });
}

/// Where the section named [name] starts and ends in [text], markers
/// included, or null when it has no complete pair of markers.
SectionSpan? _locate(String text, String name) {
  final close = sectionEnd(name);
  final starts = sectionStart(name).allMatches(text).toList().reversed;

  for (final Match(:start) in starts) {
    final end = text.indexOf(close, start);
    if (end != -1) return SectionSpan(start: start, end: end + close.length);
  }
  return null;
}
