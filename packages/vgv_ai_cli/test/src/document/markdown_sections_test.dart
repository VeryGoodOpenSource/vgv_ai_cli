import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/markdown_sections.dart';

void main() {
  group('markdown sections', () {
    test('are delimited by named markers', () {
      expect(sectionStart('persona'), '<!-- vgv-ai-cli:persona -->');
      expect(sectionEnd('persona'), '<!-- /vgv-ai-cli:persona -->');
    });

    group('upsertSection', () {
      final start = sectionStart('a');
      final end = sectionEnd('a');

      test('writes the section into an empty file', () {
        expect(upsertSection('\n', 'a', 'body\n\n'), '$start\nbody\n$end\n');
      });

      test("appends the section after the user's text", () {
        expect(
          upsertSection('Mine.\n\n', 'a', 'body'),
          'Mine.\n\n$start\nbody\n$end\n',
        );
      });

      test('replaces only the section of the same name', () {
        final b = '${sectionStart('b')}\nb\n${sectionEnd('b')}';
        final text = 'Mine.\n\n$start\nold\n$end\n\n$b\n';

        expect(
          upsertSection(text, 'a', 'new'),
          'Mine.\n\n$start\nnew\n$end\n\n$b\n',
        );
      });

      test('appends a fresh section when its end marker is missing', () {
        expect(
          upsertSection('$start\nhalf\n', 'a', 'body'),
          '$start\nhalf\n\n$start\nbody\n$end\n',
        );
      });

      test('appends a fresh section when the markers are reversed', () {
        final once = upsertSection('$end\nMine.\n', 'a', 'body');

        expect(once, '$end\nMine.\n\n$start\nbody\n$end\n');
        expect(upsertSection(once, 'a', 'body'), once);
      });

      test('keeps the text before a stray end marker after the section', () {
        final text = '$start\nold\n$end\nMine.\n$end\n';
        final once = upsertSection(text, 'a', 'new');

        expect(once, '$start\nnew\n$end\nMine.\n$end\n');
        expect(upsertSection(once, 'a', 'new'), once);
      });

      test('keeps the text after a stray start marker before the section', () {
        final text = '$start\nMine.\n$start\nold\n$end\n';
        final once = upsertSection(text, 'a', 'new');

        expect(once, '$start\nMine.\n$start\nnew\n$end\n');
        expect(upsertSection(once, 'a', 'new'), once);
      });

      test('pairs past a stray start marker after the section', () {
        final text = '$start\nold\n$end\nMine.\n$start\n';
        final once = upsertSection(text, 'a', 'new');

        expect(once, '$start\nnew\n$end\nMine.\n$start\n');
        expect(upsertSection(once, 'a', 'new'), once);
      });

      test('rewrites only the last of two complete sections', () {
        final text = '$start\nfirst\n$end\nMine.\n$start\nsecond\n$end\n';

        expect(
          upsertSection(text, 'a', 'new'),
          '$start\nfirst\n$end\nMine.\n$start\nnew\n$end\n',
        );
      });

      test('keeps CRLF line endings', () {
        final text = 'Mine.\r\n\r\n$start\r\nold\r\n$end\r\n';

        expect(
          upsertSection(text, 'a', 'one\ntwo'),
          'Mine.\r\n\r\n$start\r\none\r\ntwo\r\n$end\r\n',
        );
      });
    });

    group('sectionBody', () {
      final start = sectionStart('a');
      final end = sectionEnd('a');

      test('is what upsertSection wrote', () {
        final text = upsertSection('Mine.\n', 'a', 'line one\nline two\n');

        expect(sectionBody(text, 'a'), 'line one\nline two');
      });

      test('is empty for an empty section, markers adjacent or not', () {
        expect(sectionBody('$start\n\n$end\n', 'a'), '');
        expect(sectionBody('$start$end', 'a'), '');
      });

      test('is null when the section is not there', () {
        expect(sectionBody('Mine.\n', 'a'), isNull);
        expect(sectionBody('$start\nhalf\n', 'a'), isNull);
      });

      test('has LF line endings in a CRLF file', () {
        final text = upsertSection('Mine.\r\n', 'a', 'one\ntwo');

        expect(sectionBody(text, 'a'), 'one\ntwo');
      });
    });

    group('removeSection', () {
      test('takes back exactly what upsertSection added', () {
        for (final original in ['Mine.\n', '# Title\n\nBody.\n', '']) {
          final written = upsertSection(original, 'a', 'body');

          expect(removeSection(written, 'a'), original);
        }
      });

      test('keeps the text on both sides of a section in the middle', () {
        final b = '${sectionStart('b')}\nb\n${sectionEnd('b')}';
        final text = upsertSection('Mine.\n', 'a', 'a');

        expect(removeSection('$text\n$b\n', 'a'), 'Mine.\n\n$b\n');
      });

      test('keeps the text after a leading section', () {
        final text = upsertSection('', 'a', 'body');

        expect(removeSection('$text\nMine.\n', 'a'), 'Mine.\n');
      });

      test('leaves the text alone when the section is not there', () {
        expect(removeSection('Mine.\n', 'a'), 'Mine.\n');
      });

      test('keeps CRLF line endings', () {
        const original = 'Mine.\r\n';
        final written = upsertSection(original, 'a', 'body');

        expect(removeSection(written, 'a'), original);
      });
    });
  });
}
