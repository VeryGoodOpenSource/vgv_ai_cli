import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/frontmatter.dart';

void main() {
  group('parseFrontmatter', () {
    test('parses a leading YAML block', () {
      final result = parseFrontmatter('''
---
name: plan
description: Plan the work.
---

Body.
''');

      expect(result, {'name': 'plan', 'description': 'Plan the work.'});
    });

    test('normalizes CRLF line endings', () {
      final result = parseFrontmatter('---\r\nname: plan\r\n---\r\nBody.');

      expect(result, {'name': 'plan'});
    });

    test('returns null when there is no frontmatter', () {
      expect(parseFrontmatter('# Just a heading'), isNull);
    });

    test('returns null when the block is unterminated', () {
      expect(parseFrontmatter('---\nname: plan\n'), isNull);
    });

    test('returns null when the block is not a map', () {
      expect(parseFrontmatter('---\n- one\n- two\n---\n'), isNull);
    });

    test('returns null when the YAML is malformed', () {
      expect(parseFrontmatter('---\nname: : :\n---\n'), isNull);
    });
  });
}
