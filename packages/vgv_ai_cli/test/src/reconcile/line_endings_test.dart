import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/line_endings.dart';

void main() {
  group('normalizeLineEndings', () {
    test('makes CRLF text LF, and restores an edit of it to CRLF', () {
      final (:text, :restore) = normalizeLineEndings('a\r\nb\r\n');

      expect(text, 'a\nb\n');
      expect(restore('a\nb\nc\n'), 'a\r\nb\r\nc\r\n');
    });

    test('leaves LF text and its edits alone', () {
      final (:text, :restore) = normalizeLineEndings('a\nb\n');

      expect(text, 'a\nb\n');
      expect(restore('a\nb\nc\n'), 'a\nb\nc\n');
    });
  });
}
