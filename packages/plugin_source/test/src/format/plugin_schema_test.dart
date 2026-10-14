import 'package:ack/ack.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:plugin_source/src/format/plugin_schema.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Matcher _throwsParseException(String path, Object message) => throwsA(
  isA<PluginParseException>()
      .having((e) => e.path, 'path', path)
      .having((e) => e.message, 'message', message),
);

void main() {
  final hooks = Ack.object({
    'hooks': Ack.map(
      Ack.list(
        Ack.object({
          'hooks': Ack.list(Ack.object({'command': Ack.string()})),
        }),
      ),
    ),
  });

  group('decode', () {
    test('returns the validated value', () {
      final value = Ack.object({'name': Ack.string()})
          .decode({'name': 'a'}, path: 'plugin.json');

      expect(value, {'name': 'a'});
    });

    test('accepts a YamlMap', () {
      final value = Ack.object({'name': Ack.string()})
          .decode(loadYaml('name: a'), path: 'a.md');

      expect(value['name'], 'a');
    });

    test('names the deepest failing field and its leaf message', () {
      expect(
        () => hooks.decode({
          'hooks': {
            'Pre': [
              {
                'hooks': [
                  {'command': 1},
                ],
              },
            ],
          },
        }, path: 'hooks.json'),
        _throwsParseException(
          'hooks.json',
          allOf(
            contains('#/hooks/Pre/0/hooks/0/command'),
            contains('Expected string'),
          ),
        ),
      );
    });
  });

  group('decodeJson', () {
    test('decodes JSON text against the schema', () {
      final value = Ack.object({'name': Ack.string()})
          .decodeJson('{"name": "a"}', path: 'plugin.json');

      expect(value['name'], 'a');
    });

    test('names the deepest failing field', () {
      expect(
        () => hooks.decodeJson(
          '{"hooks": {"Pre": [{"hooks": [{"command": 1}]}]}}',
          path: 'hooks.json',
        ),
        _throwsParseException(
          'hooks.json',
          allOf(
            contains('#/hooks/Pre/0/hooks/0/command'),
            contains('Expected string'),
          ),
        ),
      );
    });

    test('throws when the document is valid JSON but not an object', () {
      expect(
        () => hooks.decodeJson('[1, 2]', path: 'hooks.json'),
        _throwsParseException('hooks.json', contains('Expected object')),
      );
    });

    test('converts invalid JSON into a PluginParseException', () {
      // jsonDecode throws FormatException, which the command runner renders
      // as a CLI usage error.
      expect(
        () => hooks.decodeJson('{not json', path: '.mcp.json'),
        allOf(
          _throwsParseException('.mcp.json', isNotEmpty),
          isNot(throwsA(isA<FormatException>())),
        ),
      );
    });
  });
}
