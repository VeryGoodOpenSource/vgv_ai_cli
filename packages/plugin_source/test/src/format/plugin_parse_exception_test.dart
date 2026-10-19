import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:test/test.dart';

void main() {
  group(PluginParseException, () {
    test('is not a FormatException', () {
      expect(
        const PluginParseException('a.md', 'bad'),
        isNot(isA<FormatException>()),
      );
    });

    test('names the file and the parser message', () {
      expect(
        const PluginParseException('skills/a/SKILL.md', 'no fence').toString(),
        allOf(contains('skills/a/SKILL.md'), contains('no fence')),
      );
    });
  });
}
