import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/document/document.dart';

/// Reading and editing a markdown file's managed sections in tests.
extension MarkdownFile on File {
  /// Writes [body] into the section named [name], as a user editing the
  /// file would.
  void editSection(String name, String body) => writeAsStringSync(
    MarkdownText(readAsStringSync()).upsertSection(name, body).source,
  );

  /// The body of the section named [name].
  String? sectionBody(String name) =>
      MarkdownText(readAsStringSync()).sectionBody(name);
}
