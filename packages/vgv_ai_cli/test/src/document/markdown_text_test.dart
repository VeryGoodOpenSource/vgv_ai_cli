import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/document.dart';

void main() {
  group('MarkdownText', () {
    final start = MarkdownText.sectionStart('a');
    final end = MarkdownText.sectionEnd('a');
    final b =
        '${MarkdownText.sectionStart('b')}\nb\n${MarkdownText.sectionEnd('b')}';

    String upsert(String text, String body) =>
        MarkdownText(text).upsertSection('a', body).source;

    test('delimits sections by named markers', () {
      expect(
        MarkdownText.sectionStart('persona'),
        '<!-- vgv-ai-cli:persona -->',
      );
      expect(
        MarkdownText.sectionEnd('persona'),
        '<!-- /vgv-ai-cli:persona -->',
      );
    });

    group('upsertSection', () {
      test('writes the section into an empty file', () {
        expect(upsert('\n', 'body\n\n'), '$start\nbody\n$end\n');
      });

      test("appends the section after the user's text", () {
        expect(upsert('Mine.\n\n', 'body'), 'Mine.\n\n$start\nbody\n$end\n');
      });

      test('replaces only the section of the same name', () {
        expect(
          upsert('Mine.\n\n$start\nold\n$end\n\n$b\n', 'new'),
          'Mine.\n\n$start\nnew\n$end\n\n$b\n',
        );
      });

      test('appends a fresh section when its end marker is missing', () {
        expect(
          upsert('$start\nhalf\n', 'body'),
          '$start\nhalf\n\n$start\nbody\n$end\n',
        );
      });

      test('appends a fresh section when the markers are reversed', () {
        final once = upsert('$end\nMine.\n', 'body');

        expect(once, '$end\nMine.\n\n$start\nbody\n$end\n');
        expect(upsert(once, 'body'), once);
      });

      test('keeps the text before a stray end marker after the section', () {
        final once = upsert('$start\nold\n$end\nMine.\n$end\n', 'new');

        expect(once, '$start\nnew\n$end\nMine.\n$end\n');
        expect(upsert(once, 'new'), once);
      });

      test('keeps the text after a stray start marker before the section', () {
        final once = upsert('$start\nMine.\n$start\nold\n$end\n', 'new');

        expect(once, '$start\nMine.\n$start\nnew\n$end\n');
        expect(upsert(once, 'new'), once);
      });

      test('pairs past a stray start marker after the section', () {
        final once = upsert('$start\nold\n$end\nMine.\n$start\n', 'new');

        expect(once, '$start\nnew\n$end\nMine.\n$start\n');
        expect(upsert(once, 'new'), once);
      });

      test('rewrites only the last of two complete sections', () {
        expect(
          upsert('$start\nfirst\n$end\nMine.\n$start\nsecond\n$end\n', 'new'),
          '$start\nfirst\n$end\nMine.\n$start\nnew\n$end\n',
        );
      });

      test('keeps CRLF line endings', () {
        expect(
          upsert('Mine.\r\n\r\n$start\r\nold\r\n$end\r\n', 'one\ntwo'),
          'Mine.\r\n\r\n$start\r\none\r\ntwo\r\n$end\r\n',
        );
      });
    });

    group('sectionBody', () {
      test('is what upsertSection wrote', () {
        final text = const MarkdownText('Mine.\n')
            .upsertSection('a', 'line one\nline two\n');

        expect(text.sectionBody('a'), 'line one\nline two');
      });

      test('is empty for an empty section, markers adjacent or not', () {
        expect(MarkdownText('$start\n\n$end\n').sectionBody('a'), '');
        expect(MarkdownText('$start$end').sectionBody('a'), '');
      });

      test('is null when the section is not there', () {
        expect(const MarkdownText('Mine.\n').sectionBody('a'), isNull);
        expect(MarkdownText('$start\nhalf\n').sectionBody('a'), isNull);
      });

      test('has LF line endings in a CRLF file', () {
        final text = const MarkdownText('Mine.\r\n')
            .upsertSection('a', 'one\ntwo');

        expect(text.sectionBody('a'), 'one\ntwo');
      });
    });

    group('removeSection', () {
      String remove(String text) =>
          MarkdownText(text).removeSection('a').source;

      test('takes back exactly what upsertSection added', () {
        for (final original in ['Mine.\n', '# Title\n\nBody.\n', '']) {
          expect(remove(upsert(original, 'body')), original);
        }
      });

      test('keeps the text on both sides of a section in the middle', () {
        expect(remove('${upsert('Mine.\n', 'a')}\n$b\n'), 'Mine.\n\n$b\n');
      });

      test('keeps the text after a leading section', () {
        expect(remove('${upsert('', 'body')}\nMine.\n'), 'Mine.\n');
      });

      test('leaves the text alone when the section is not there', () {
        const text = MarkdownText('Mine.\n');

        expect(text.removeSection('a'), same(text));
      });

      test('keeps CRLF line endings', () {
        expect(remove(upsert('Mine.\r\n', 'body')), 'Mine.\r\n');
      });
    });
  });
}
