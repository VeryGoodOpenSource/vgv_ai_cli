import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/markdown_sections.dart';

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
    });
  });
}
