import 'package:test/test.dart';
import 'package:vgv_ai_plugins/src/format/plugin_parse_exception.dart';

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
