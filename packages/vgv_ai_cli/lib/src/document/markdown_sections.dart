import 'package:vgv_ai_cli/src/document/model/model.dart';

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

/// The body of the section named [name] in [original], as [upsertSection]
/// wrote it, or null when [original] has no such section.
///
/// The body has `\n` line endings whatever the file's, so it hashes the same
/// as the body install wrote.
String? sectionBody(String original, String name) {
  final NormalizedText(:text) = NormalizedText.from(original);
  return switch (_locate(text, name)) {
    SectionSpan(:final start, :final end) =>
      text
          .substring(
            start + sectionStart(name).length,
            end - sectionEnd(name).length,
          )
          .replaceFirst(RegExp(r'^\n'), '')
          .replaceFirst(RegExp(r'\n$'), ''),
    null => null,
  };
}

/// [original] without the section named [name], and the blank line
/// [upsertSection] put before it, and unchanged when there is no such
/// section. The file keeps its line endings.
String removeSection(String original, String name) {
  final NormalizedText(:text, :restore) = NormalizedText.from(original);
  final located = _locate(text, name);
  if (located == null) return original;

  final before = text.substring(0, located.start).trimRight();
  final after = text.substring(located.end).replaceFirst(RegExp(r'^\n+'), '');
  return restore(switch ((before.isEmpty, after.isEmpty)) {
    (true, _) => after,
    (false, true) => '$before\n',
    (false, false) => '$before\n\n$after',
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
