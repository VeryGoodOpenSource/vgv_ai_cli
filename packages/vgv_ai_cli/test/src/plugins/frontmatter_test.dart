import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/frontmatter.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('splitFrontmatter', () {
    test('parses frontmatter and body', () {
      final result = splitFrontmatter('---\nname: a\n---\n\n# Title\n');

      expect(result.data, {'name': 'a'});
      expect(result.body, '# Title');
    });

    test('treats a document without a leading fence as all body', () {
      final result = splitFrontmatter('# Title\n\nname: not-frontmatter\n');

      expect(result.data, isEmpty);
      expect(result.body, '# Title\n\nname: not-frontmatter');
    });

    test('treats an unterminated fence as all body', () {
      final result = splitFrontmatter('---\nname: a\n\n# Title\n');

      expect(result.data, isEmpty);
      expect(result.body, '---\nname: a\n\n# Title');
    });

    test('stops at the first closing fence, not the last', () {
      final result = splitFrontmatter(
        '---\nname: a\n---\n\nintro\n\n---\n\nafter the rule\n',
      );

      expect(result.data, {'name': 'a'});
      expect(result.body, 'intro\n\n---\n\nafter the rule');
    });

    test('preserves every markdown rule in the body', () {
      final result = splitFrontmatter(
        '---\nname: a\n---\n\none\n\n---\n\ntwo\n\n---\n\nthree\n',
      );

      expect('---'.allMatches(result.body).length, 2);
      expect(result.body, endsWith('three'));
    });

    test('normalizes CRLF to LF', () {
      final crlf = splitFrontmatter('---\r\nname: a\r\n---\r\n\r\nbody\r\n');
      final lf = splitFrontmatter('---\nname: a\n---\n\nbody\n');

      expect(crlf.data, lf.data);
      expect(crlf.body, lf.body);
      expect(crlf.body, isNot(contains('\r')));
    });

    test('returns empty data for empty frontmatter', () {
      final result = splitFrontmatter('---\n---\n\nbody\n');

      expect(result.data, isEmpty);
      expect(result.body, 'body');
    });

    test('keeps a literal block scalar verbatim', () {
      final result = splitFrontmatter(
        '---\ndescription: |\n  line one\n\n  <tag>x</tag>\n---\n\nbody\n',
      );

      expect(result.data['description'], 'line one\n\n<tag>x</tag>\n');
    });

    test('folds a folded block scalar', () {
      final result = splitFrontmatter(
        '---\ndescription: >\n  line one\n  line two\n---\n\nbody\n',
      );

      expect(result.data['description'], 'line one line two\n');
    });

    test('throws FormatException when frontmatter is not a mapping', () {
      expect(
        () => splitFrontmatter('---\n- one\n- two\n---\n\nbody\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws YamlException on malformed YAML', () {
      expect(
        () => splitFrontmatter('---\nname: [unclosed\n---\n\nbody\n'),
        throwsA(isA<YamlException>()),
      );
    });
  });

  group('toSortedJson', () {
    test('sorts map keys recursively', () {
      final yaml = loadYaml('b: 1\na:\n  d: 2\n  c: 3\n');

      expect(toSortedJson(yaml), {
        'a': {'c': 3, 'd': 2},
        'b': 1,
      });
      expect((toSortedJson(yaml)! as Map<String, dynamic>).keys.toList(), [
        'a',
        'b',
      ]);
    });

    test('converts lists and nested maps', () {
      final yaml = loadYaml('items:\n  - name: x\n  - name: y\n');

      expect(toSortedJson(yaml), {
        'items': [
          {'name': 'x'},
          {'name': 'y'},
        ],
      });
    });

    test('stringifies non-string map keys', () {
      final yaml = loadYaml('1: one\n2: two\n');

      expect(toSortedJson(yaml), {'1': 'one', '2': 'two'});
    });

    test('sorts plain Dart maps as well as YAML maps', () {
      expect(
        (toSortedJson({'b': 1, 'a': 2})! as Map<String, dynamic>).keys.toList(),
        ['a', 'b'],
      );
    });

    test('passes scalars through', () {
      expect(toSortedJson(null), isNull);
      expect(toSortedJson('text'), 'text');
      expect(toSortedJson(7), 7);
      expect(toSortedJson(true), isTrue);
    });
  });
}
