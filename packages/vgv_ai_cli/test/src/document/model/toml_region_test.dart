import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/model/model.dart';

void main() {
  group(TomlRegion, () {
    TomlStatement statement(TomlStatementKind kind, List<String> path) =>
        TomlStatement(
          kind: kind,
          start: 0,
          end: 0,
          path: path,
          comment: '',
          hasInnerComment: false,
        );

    test('finds the pair that sets a key, and nothing else', () {
      final pair = statement(TomlStatementKind.keyValue, ['model']);
      final region = TomlRegion(
        header: statement(TomlStatementKind.table, ['model']),
        body: [
          statement(TomlStatementKind.other, const []),
          statement(TomlStatementKind.keyValue, ['a', 'model']),
          pair,
        ],
      );

      expect(region.statementOf('model'), same(pair));
      expect(region.statementOf('theme'), isNull);
    });
  });
}
