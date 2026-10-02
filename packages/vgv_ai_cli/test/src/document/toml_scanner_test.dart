import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/document.dart';

Matcher _statement(
  TomlStatementKind kind, {
  required List<String> path,
  required int start,
  required int end,
  String comment = '',
  bool hasInnerComment = false,
}) => isA<TomlStatement>()
    .having((s) => s.kind, 'kind', kind)
    .having((s) => s.path, 'path', path)
    .having((s) => s.start, 'start', start)
    .having((s) => s.end, 'end', end)
    .having((s) => s.comment, 'comment', comment)
    .having((s) => s.hasInnerComment, 'hasInnerComment', hasInnerComment);

List<TomlStatement> _topLevel(List<String> lines) =>
    TomlScanner(lines).region(table: const [])!.body;

void main() {
  group('TomlScanner', () {
    const lines = [
      'model = "o3"',
      '',
      '[mcp]',
      'args = [',
      '  "serve", # inline',
      ']',
      '[[agents]]',
      'name = "review"',
    ];

    test('is the statements before the first header for the top level', () {
      final region = TomlScanner(lines).region(table: const [])!;

      expect(region.header, isNull);
      expect(region.body, [
        _statement(
          TomlStatementKind.keyValue,
          path: ['model'],
          start: 0,
          end: 0,
        ),
        _statement(TomlStatementKind.other, path: const [], start: 1, end: 1),
      ]);
    });

    test('is a table up to the next header, a multiline value as one', () {
      final region = TomlScanner(lines).region(table: const ['mcp'])!;

      expect(
        region.header,
        _statement(TomlStatementKind.table, path: ['mcp'], start: 2, end: 2),
      );
      expect(region.body, [
        _statement(
          TomlStatementKind.keyValue,
          path: ['args'],
          start: 3,
          end: 5,
          hasInnerComment: true,
        ),
      ]);
    });

    test('does not let an array-of-tables header stand in for a table', () {
      expect(TomlScanner(lines).region(table: const ['agents']), isNull);
    });

    test('is null for a table that appears nowhere in the document', () {
      expect(TomlScanner(lines).region(table: const ['theme']), isNull);
    });

    test('reads quoted keys whose quotes hold the terminator', () {
      const quoted = ['"a=b".c = 1', '["x]y"]', 'd = 2'];

      expect(_topLevel(quoted), [
        _statement(
          TomlStatementKind.keyValue,
          path: ['a=b', 'c'],
          start: 0,
          end: 0,
        ),
      ]);
      expect(
        TomlScanner(quoted).region(table: const ['x]y'])?.header,
        _statement(TomlStatementKind.table, path: ['x]y'], start: 1, end: 1),
      );
    });

    test('is one statement for a basic multiline string with escapes', () {
      expect(_topLevel(const ['doc = """', r'say \""" hi', '"""', 'b = 1']), [
        _statement(TomlStatementKind.keyValue, path: ['doc'], start: 0, end: 2),
        _statement(TomlStatementKind.keyValue, path: ['b'], start: 3, end: 3),
      ]);
    });

    test('is one statement for a literal multiline string holding #', () {
      expect(_topLevel(const ["note = '''", '# not a comment', "'''"]), [
        _statement(
          TomlStatementKind.keyValue,
          path: ['note'],
          start: 0,
          end: 2,
        ),
      ]);
    });

    test('finds a comment only outside strings', () {
      expect(
        _topLevel(const ["path = 'a#b' # real", r'say = "a\"#b"', '# note']),
        [
          _statement(
            TomlStatementKind.keyValue,
            path: ['path'],
            start: 0,
            end: 0,
            comment: ' # real',
          ),
          _statement(
            TomlStatementKind.keyValue,
            path: ['say'],
            start: 1,
            end: 1,
          ),
          _statement(
            TomlStatementKind.other,
            path: const [],
            start: 2,
            end: 2,
            comment: '# note',
          ),
        ],
      );
    });

    test('ends an unterminated string at the end of its line', () {
      expect(_topLevel(const ['bad = "open', 'b = 1']), [
        _statement(TomlStatementKind.keyValue, path: ['bad'], start: 0, end: 0),
        _statement(TomlStatementKind.keyValue, path: ['b'], start: 1, end: 1),
      ]);
    });

    test('ends an array still open at the end of the document there', () {
      expect(_topLevel(const ['args = [', '  "a",']), [
        _statement(
          TomlStatementKind.keyValue,
          path: ['args'],
          start: 0,
          end: 1,
        ),
      ]);
    });

    test('has an empty path for a key TOML rejects', () {
      expect(_topLevel(const ['a..b = 1']), [
        _statement(
          TomlStatementKind.keyValue,
          path: const [],
          start: 0,
          end: 0,
        ),
      ]);
    });
  });
}
