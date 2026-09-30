import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/model/model.dart';

void main() {
  group('NormalizedText', () {
    group('from', () {
      test('makes CRLF text LF, and restores an edit of it to CRLF', () {
        final normalized = NormalizedText.from('a\r\nb\r\n');

        expect(normalized.text, 'a\nb\n');
        expect(normalized.restore('a\nb\nc\n'), 'a\r\nb\r\nc\r\n');
      });

      test('leaves LF text and its edits alone', () {
        final normalized = NormalizedText.from('a\nb\n');

        expect(normalized.text, 'a\nb\n');
        expect(normalized.restore('a\nb\nc\n'), 'a\nb\nc\n');
      });
    });
  });
}
