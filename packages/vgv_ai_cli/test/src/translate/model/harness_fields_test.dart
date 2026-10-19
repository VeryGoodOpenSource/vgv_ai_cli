import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  group(HarnessFields, () {
    test('keys every field it has as the brick reads it', () {
      const fields = HarnessFields(frontmatter: '---\n---\n', toml: 'a = 1\n');

      expect(fields.toMap(), {'frontmatter': '---\n---\n', 'toml': 'a = 1\n'});
    });

    test('leaves out every field it does not have', () {
      expect(const HarnessFields().toMap(), isEmpty);
    });

    test('compares by value', () {
      expect(
        const HarnessFields(toml: 'a = 1\n'),
        const HarnessFields(toml: 'a = 1\n'),
      );
      expect(
        const HarnessFields(toml: 'a = 1\n'),
        isNot(const HarnessFields(frontmatter: 'a = 1\n')),
      );
    });
  });
}
