import 'package:plugin_source/src/format/frontmatter.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Frontmatter _parse(String source) => Frontmatter.parse(source, path: 'a.md');

Matcher _throwsParseException(Object messageMatcher) => throwsA(
  isA<PluginParseException>().having(
    (e) => e.message,
    'message',
    messageMatcher,
  ),
);

void main() {
  group('Frontmatter.parse', () {
    test('splits frontmatter from body', () {
      final frontmatter = _parse('---\nname: a\n---\n\n# Body\n');

      expect(frontmatter.name, 'a');
      expect(frontmatter.body, '# Body\n');
    });

    test('does not treat a horizontal rule as the closing fence', () {
      // The prototype searched for the substring '\n---' and swallowed half
      // the document on any skill whose body used a rule.
      final frontmatter = _parse(
        '---\nname: a\n---\n\n# Body\n\n---\n\nStill body.\n',
      );

      expect(frontmatter.name, 'a');
      expect(frontmatter.body, contains('Still body.'));
    });

    test('handles CRLF line endings', () {
      expect(_parse('---\r\nname: a\r\n---\r\n\r\n# Body\r\n').name, 'a');
    });

    group('rejects', () {
      test('a document with no opening fence', () {
        expect(
          () => _parse('# Just a body\n'),
          _throwsParseException(contains('no opening')),
        );
      });

      test('an unterminated fence', () {
        expect(
          () => _parse('---\nname: a\n\n# Body never closes\n'),
          _throwsParseException(contains('unterminated')),
        );
      });

      test('frontmatter that parses as a scalar', () {
        expect(
          () => _parse('---\njust prose, no colon\n---\n\nbody\n'),
          _throwsParseException(contains('key/value')),
        );
      });

      test('frontmatter that parses as a list', () {
        expect(
          () => _parse('---\n- a\n- b\n---\n\nbody\n'),
          _throwsParseException(contains('key/value')),
        );
      });

      test('empty frontmatter', () {
        expect(
          () => _parse('---\n---\n\nbody\n'),
          _throwsParseException(contains('nothing')),
        );
      });

      test('malformed YAML', () {
        expect(
          () => _parse('---\nname: [unclosed\n---\n\nbody\n'),
          throwsA(isA<PluginParseException>()),
        );
      });
    });

    test('never throws a FormatException', () {
      // YamlException implements FormatException, which the command runner
      // renders as a CLI usage error. Every failure mode must be converted.
      const malformed = [
        '# no fence\n',
        '---\nname: a\n',
        '---\nprose\n---\n',
        '---\n- a\n---\n',
        '---\n---\n',
        '---\nname: [unclosed\n---\n',
      ];

      for (final source in malformed) {
        expect(
          () => _parse(source),
          isNot(throwsA(isA<FormatException>())),
          reason: 'must not surface as a usage error for: $source',
        );
      }
    });

    test('rejects a non-string key, naming it', () {
      // YAML admits an unquoted `2:`, which the schema would reject without
      // naming the key.
      expect(
        () => _parse('---\n2: x\n---\n'),
        _throwsParseException('#: key 2 must be a string'),
      );
    });

    test('rejects a nested non-string key, naming where it is', () {
      expect(
        () => _parse('---\nmetadata:\n  2: x\n---\n'),
        _throwsParseException('#/metadata: key 2 must be a string'),
      );
    });

    test('rejects a non-string key inside a list, naming where it is', () {
      expect(
        () => _parse('---\nhooks:\n  - true: x\n---\n'),
        _throwsParseException('#/hooks/0: key true must be a string'),
      );
    });

    test('escapes a slash or tilde in the keys it names', () {
      expect(
        () => _parse('---\n"a/b~c":\n  2: x\n---\n'),
        _throwsParseException('#/a~1b~0c: key 2 must be a string'),
      );
    });

    test('rejects a non-string name, naming the field', () {
      expect(
        () => _parse('---\nname: 2\n---\n'),
        _throwsParseException(contains('#/name')),
      );
    });

    test('rejects skills that are neither a list nor a string', () {
      expect(
        () => _parse('---\nskills: 2\n---\n'),
        _throwsParseException(contains('#/skills')),
      );
    });

    test('converts nested structures to plain Dart collections', () {
      // Agents nest `hooks:` that no other harness reads back. loadYaml
      // returns YamlMap/YamlList, which downstream writers serialize
      // inconsistently, so the boundary normalizes them here.
      final frontmatter = _parse(
        '---\nname: a\nhooks:\n  PreToolUse:\n    - matcher: "Bash"\n---\n',
      );

      final hooks = frontmatter.values['hooks']! as Map<String, Object?>;
      final entries = hooks['PreToolUse']! as List<Object?>;
      final first = entries.single! as Map<String, Object?>;

      expect(hooks, isNot(isA<YamlMap>()));
      expect(entries, isNot(isA<YamlList>()));
      expect(first['matcher'], 'Bash');
    });
  });

  group('description', () {
    test('flattens a literal block onto one line', () {
      final frontmatter = _parse('---\ndescription: |\n  One.\n  Two.\n---\n');

      expect(frontmatter.description, 'One. Two.');
    });

    test('flattens a folded block onto one line', () {
      final frontmatter = _parse('---\ndescription: >\n  One.\n  Two.\n---\n');

      expect(frontmatter.description, 'One. Two.');
    });

    test('is empty when absent', () {
      expect(_parse('---\nname: a\n---\n').description, isEmpty);
    });
  });

  group('oneLine', () {
    test('flattens any key, not only the description', () {
      final frontmatter = _parse('---\nwhen_to_use: >\n  One.\n  Two.\n---\n');

      expect(frontmatter.oneLine('when_to_use'), 'One. Two.');
    });

    test('is null when the key is absent', () {
      expect(_parse('---\nname: a\n---\n').oneLine('when_to_use'), isNull);
    });
  });

  group('skills', () {
    test('parses an inline list', () {
      expect(_parse('---\nskills: [a, b]\n---\n').skills, ['a', 'b']);
    });

    test('parses a block sequence', () {
      expect(_parse('---\nskills:\n  - a\n  - b\n---\n').skills, ['a', 'b']);
    });

    test('splits a comma-separated string', () {
      expect(_parse('---\nskills: a, b\n---\n').skills, ['a', 'b']);
    });

    test('parses a bare scalar as one entry', () {
      expect(_parse('---\nskills: a\n---\n').skills, ['a']);
    });

    test('is empty when absent', () {
      expect(_parse('---\nname: a\n---\n').skills, isEmpty);
    });

    test('drops blank entries', () {
      expect(_parse('---\nskills: [a, "", b]\n---\n').skills, ['a', 'b']);
    });
  });

  // allowed-tools and user-invocable are Claude-specific interpretations and
  // live in ClaudePluginParser; their tests are in
  // parser/claude_plugin_parser_test.dart.

  group('name', () {
    test('is null when absent', () {
      expect(_parse('---\ndescription: a\n---\n').name, isNull);
    });
  });

  group('Frontmatter.render', () {
    /// Renders then parses, so every case proves the two agree rather than
    /// asserting on a formatting choice that could drift.
    Frontmatter roundTrip(Map<String, Object?> values) =>
        _parse('${Frontmatter.render(values)}\nbody\n');

    test('renders nothing for an empty map', () {
      // An empty fence is not a valid frontmatter block, so emit no block.
      expect(Frontmatter.render(const {}), isEmpty);
    });

    test('round-trips a plain string', () {
      expect(roundTrip({'name': 'testing'}).values['name'], 'testing');
    });

    test('round-trips a string carrying YAML indicator characters', () {
      const awkward = 'Use when: reviewing #code, [maybe] {always}';

      expect(
        roundTrip({'description': awkward}).values['description'],
        awkward,
      );
    });

    test('round-trips a string that looks like a bool', () {
      // Emitted plain, `yes` parses back as a boolean rather than a string.
      expect(roundTrip({'name': 'yes'}).values['name'], 'yes');
    });

    test('round-trips a string that looks like a number', () {
      expect(roundTrip({'name': '1.0'}).values['name'], '1.0');
    });

    test('round-trips a string containing a quote and a backslash', () {
      const awkward = r'He said "run C:\dart" loudly';

      expect(roundTrip({'name': awkward}).values['name'], awkward);
    });

    test('round-trips a multi-line string as a literal block', () {
      // The plugins write descriptions as folded and literal block scalars.
      const multi = 'First line.\nSecond line.';

      final rendered = Frontmatter.render({'description': multi});

      expect(rendered, contains('|2-'));
      expect(roundTrip({'description': multi}).values['description'], multi);
    });

    test('round-trips a multi-line string whose first line is indented', () {
      const indented = '  indented first\nthen flush';

      expect(
        roundTrip({'description': indented}).values['description'],
        indented,
      );
    });

    test('round-trips a multi-line string inside a list', () {
      const multi = 'First line.\nSecond line.';

      expect(
        roundTrip({
          'notes': [multi, 'single'],
        }).values['notes'],
        [multi, 'single'],
      );
    });

    test('round-trips a multi-line string inside a nested map', () {
      const multi = '  First line.\nSecond line.';

      expect(
        roundTrip({
          'outer': {'inner': multi},
        }).values['outer'],
        {'inner': multi},
      );
    });

    test('refuses a collection inside a list', () {
      expect(
        () => Frontmatter.render({
          'servers': [
            {'name': 'dart'},
          ],
        }),
        throwsArgumentError,
      );
    });

    test('round-trips a string containing a tab', () {
      expect(roundTrip({'name': 'a\tb'}).values['name'], 'a\tb');
    });

    test('round-trips a list', () {
      expect(
        roundTrip({
          'keywords': ['a', 'b'],
        }).values['keywords'],
        ['a', 'b'],
      );
    });

    test('round-trips a nested map', () {
      final parsed = roundTrip({
        'metadata': {'type': 'reference', 'level': 2},
      });

      expect(parsed.values['metadata'], {'type': 'reference', 'level': 2});
      expect(parsed.values['metadata'], isA<Map<String, Object?>>());
    });

    test('round-trips a bool and a number', () {
      final parsed = roundTrip({'enabled': true, 'weight': 3});

      expect(parsed.values['enabled'], isTrue);
      expect(parsed.values['weight'], 3);
    });

    test('renders a null as an empty value', () {
      expect(roundTrip({'license': null}).values['license'], isNull);
    });

    test('renders an empty list and map as quoted scalars', () {
      // Neither has a useful block form; stringifying keeps the document
      // parseable instead of emitting a dangling key.
      final parsed = roundTrip({'a': <String>[], 'b': <String, Object?>{}});

      expect(parsed.values['a'], '[]');
      expect(parsed.values['b'], '{}');
    });

    test('round-trips the body beneath it', () {
      final rendered = Frontmatter.render({'name': 'a'});

      expect(_parse('$rendered\n# Body\n').body, '# Body\n');
    });
  });
}
