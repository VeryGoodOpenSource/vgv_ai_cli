import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/json_object.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/plugin_parse_exception.dart';

void main() {
  group('parseJsonObject', () {
    test('wraps a JSON object in a ConfigMap', () {
      final config = parseJsonObject(
        '{"mcpServers": {"dart": {"command": "dart"}}}',
        path: '.mcp.json',
      );

      expect(
        config.child('mcpServers')!.child('dart')!.string('command'),
        'dart',
      );
    });

    test('throws when the document is valid JSON but not an object', () {
      expect(
        () => parseJsonObject('[1, 2]', path: 'hooks.json'),
        throwsA(
          isA<PluginParseException>()
              .having((e) => e.path, 'path', 'hooks.json')
              .having((e) => e.message, 'message', contains('JSON object')),
        ),
      );
    });

    test('converts invalid JSON into a PluginParseException', () {
      // jsonDecode throws FormatException, which the command runner renders
      // as a CLI usage error.
      expect(
        () => parseJsonObject('{not json', path: '.mcp.json'),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.path,
            'path',
            '.mcp.json',
          ),
        ),
      );
      expect(
        () => parseJsonObject('{not json', path: '.mcp.json'),
        isNot(throwsA(isA<FormatException>())),
      );
    });
  });
}
