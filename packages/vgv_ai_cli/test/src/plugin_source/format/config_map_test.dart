import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/config_map.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/plugin_parse_exception.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('ConfigMap.parseJson', () {
    test('wraps a JSON object in a ConfigMap', () {
      final config = ConfigMap.parseJson(
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
        () => ConfigMap.parseJson('[1, 2]', path: 'hooks.json'),
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
        () => ConfigMap.parseJson('{not json', path: '.mcp.json'),
        throwsA(
          isA<PluginParseException>().having(
            (e) => e.path,
            'path',
            '.mcp.json',
          ),
        ),
      );
      expect(
        () => ConfigMap.parseJson('{not json', path: '.mcp.json'),
        isNot(throwsA(isA<FormatException>())),
      );
    });
  });

  group('ConfigMap.of', () {
    test('wraps a plain map', () {
      final config = ConfigMap.of({'name': 'a'});

      expect(config.string('name'), 'a');
    });

    test('normalizes a YamlMap into plain collections', () {
      final document = loadYaml('name: a\nhooks:\n  PreToolUse:\n    - x: 1\n');

      final config = ConfigMap.of(document);
      final hooks = config.child('hooks')!;
      final registrations = hooks['PreToolUse']! as List<Object?>;

      expect(config.values, isNot(isA<YamlMap>()));
      expect(registrations, isNot(isA<YamlList>()));
      expect(registrations.single, isA<Map<String, Object?>>());
    });

    test('stringifies non-string keys', () {
      final config = ConfigMap.of(loadYaml('2: x\n'));

      expect(config.values.keys, contains('2'));
    });

    test('yields an empty view for a non-map source', () {
      expect(ConfigMap.of('just a scalar').values, isEmpty);
      expect(ConfigMap.of(null).values, isEmpty);
    });
  });

  group('operator []', () {
    test('returns the raw value', () {
      expect(ConfigMap.of({'k': 42})['k'], 42);
    });

    test('returns null when absent', () {
      expect(ConfigMap.of({})['missing'], isNull);
    });
  });

  group('entries', () {
    test('exposes every key/value pair', () {
      final config = ConfigMap.of({'a': 1, 'b': 2});

      expect(config.entries.map((e) => e.key), containsAll(['a', 'b']));
    });
  });

  group('string', () {
    test('stringifies a scalar', () {
      expect(ConfigMap.of({'k': 42}).string('k'), '42');
    });

    test('is null when absent', () {
      expect(ConfigMap.of({}).string('k'), isNull);
    });
  });

  group('integer', () {
    test('returns an int value', () {
      expect(ConfigMap.of({'k': 5}).integer('k'), 5);
    });

    test('is null when the value is not an int', () {
      expect(ConfigMap.of({'k': '5'}).integer('k'), isNull);
    });

    test('is null when absent', () {
      expect(ConfigMap.of({}).integer('k'), isNull);
    });
  });

  group('boolean', () {
    test('returns a bool value', () {
      expect(ConfigMap.of({'k': false}).boolean('k'), isFalse);
    });

    test('is null when the value is not a bool', () {
      expect(ConfigMap.of({'k': 'false'}).boolean('k'), isNull);
    });

    test('is null when absent', () {
      expect(ConfigMap.of({}).boolean('k'), isNull);
    });
  });

  group('stringList', () {
    test('takes a list element-wise', () {
      expect(
        ConfigMap.of({
          'k': ['a', 'b'],
        }).stringList('k'),
        ['a', 'b'],
      );
    });

    test('drops blank list entries', () {
      expect(
        ConfigMap.of({
          'k': ['a', '', 'b'],
        }).stringList('k'),
        ['a', 'b'],
      );
    });

    test('splits a scalar string on commas', () {
      expect(ConfigMap.of({'k': 'a, b'}).stringList('k'), ['a', 'b']);
    });

    test('treats a non-string scalar as one entry', () {
      expect(ConfigMap.of({'k': 2}).stringList('k'), ['2']);
    });

    test('is empty when absent', () {
      expect(ConfigMap.of({}).stringList('k'), isEmpty);
    });
  });

  group('child', () {
    test('wraps a nested map', () {
      final config = ConfigMap.of({
        'k': {'inner': 'v'},
      });

      expect(config.child('k')!.string('inner'), 'v');
    });

    test('wraps a nested YamlMap once the parent has been normalized', () {
      // The accessors match on the normalized types, so this only holds
      // because `of` is the sole way to build a ConfigMap.
      final config = ConfigMap.of(loadYaml('k:\n  inner: v\n'));

      expect(config.child('k')!.string('inner'), 'v');
    });

    test('is null when the value is not a map', () {
      expect(ConfigMap.of({'k': 'x'}).child('k'), isNull);
    });

    test('is null when absent', () {
      expect(ConfigMap.of({}).child('k'), isNull);
    });
  });

  group('ConfigMap.maps', () {
    test('wraps every map in a list', () {
      final maps = ConfigMap.maps([
        {'a': 1},
        {'b': 2},
      ]);

      expect(maps, hasLength(2));
      expect(maps.first.integer('a'), 1);
    });

    test('drops non-map elements', () {
      expect(
        ConfigMap.maps([
          {'a': 1},
          'not a map',
        ]),
        hasLength(1),
      );
    });

    test('is empty when the value is not a list', () {
      expect(ConfigMap.maps('x'), isEmpty);
    });
  });
}
