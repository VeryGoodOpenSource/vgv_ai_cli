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

    test('throws for null, even when the schema accepts it', () {
      expect(
        () => Ack.string().nullable().decode(null, path: 'a.json'),
        _throwsParseException('a.json', '#: Expected a value, got null'),
      );
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

  group('decode, for a field with several allowed shapes,', () {
    final skills = Ack.object({
      'skills': Ack.anyOf([Ack.list(Ack.string()), Ack.string()]),
    });

    test('names every shape when the value matches none of them', () {
      expect(
        () => skills.decode({'skills': 2}, path: 'a.md'),
        _throwsParseException(
          'a.md',
          '#/skills: Expected array or string, got integer',
        ),
      );
    });

    test('describes the shape the value has, where it goes wrong', () {
      expect(
        () => skills.decode({
          'skills': ['a', 2],
        }, path: 'a.md'),
        _throwsParseException(
          'a.md',
          '#/skills/1: Expected string, got integer',
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

  group('jsonPointer', () {
    test('appends the token as a segment', () {
      expect(jsonPointer('#/hooks', 0), '#/hooks/0');
    });

    test('escapes a tilde and a slash', () {
      expect(jsonPointer('#', 'a/b~c'), '#/a~1b~0c');
    });
  });
}
