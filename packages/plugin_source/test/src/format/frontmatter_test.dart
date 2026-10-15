import 'package:plugin_source/src/format/frontmatter.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group(Frontmatter, () {
    Frontmatter parse(String source) => Frontmatter.parse(source, path: 'a.md');

    Matcher throwsParseException(Object messageMatcher) => throwsA(
      isA<PluginParseException>().having(
        (e) => e.message,
        'message',
        messageMatcher,
      ),
    );

    group('parse', () {
      test('splits frontmatter from body', () {
        final frontmatter = parse('---\nname: a\n---\n\n# Body\n');

        expect(frontmatter.name, equals('a'));
        expect(frontmatter.body, equals('# Body\n'));
      });

      test('does not treat a horizontal rule as the closing fence', () {
        // The prototype searched for the substring '\n---' and swallowed half
        // the document on any skill whose body used a rule.
        final frontmatter = parse(
          '---\nname: a\n---\n\n# Body\n\n---\n\nStill body.\n',
        );

        expect(frontmatter.name, equals('a'));
        expect(frontmatter.body, contains('Still body.'));
      });

      test('handles CRLF line endings', () {
        expect(
          parse('---\r\nname: a\r\n---\r\n\r\n# Body\r\n').name,
          equals('a'),
        );
      });

      group('rejects', () {
        test('a document with no opening fence', () {
          expect(
            () => parse('# Just a body\n'),
            throwsParseException(contains('no opening')),
          );
        });

        test('an unterminated fence', () {
          expect(
            () => parse('---\nname: a\n\n# Body never closes\n'),
            throwsParseException(contains('unterminated')),
          );
        });

        test('frontmatter that parses as a scalar', () {
          expect(
            () => parse('---\njust prose, no colon\n---\n\nbody\n'),
            throwsParseException(contains('key/value')),
          );
        });

        test('frontmatter that parses as a list', () {
          expect(
            () => parse('---\n- a\n- b\n---\n\nbody\n'),
            throwsParseException(contains('key/value')),
          );
        });

        test('empty frontmatter', () {
          expect(
            () => parse('---\n---\n\nbody\n'),
            throwsParseException(contains('nothing')),
          );
        });

        test('malformed YAML', () {
          expect(
            () => parse('---\nname: [unclosed\n---\n\nbody\n'),
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
            () => parse(source),
            isNot(throwsA(isA<FormatException>())),
            reason: 'must not surface as a usage error for: $source',
          );
        }
      });

      test('rejects a non-string key, naming it', () {
        // YAML admits an unquoted `2:`, which the schema would reject without
        // naming the key.
        expect(
          () => parse('---\n2: x\n---\n'),
          throwsParseException('#: key 2 must be a string'),
        );
      });

      test('rejects a nested non-string key, naming where it is', () {
        expect(
          () => parse('---\nmetadata:\n  2: x\n---\n'),
          throwsParseException('#/metadata: key 2 must be a string'),
        );
      });

      test('rejects a non-string key inside a list, naming where it is', () {
        expect(
          () => parse('---\nhooks:\n  - true: x\n---\n'),
          throwsParseException('#/hooks/0: key true must be a string'),
        );
      });

      test('escapes a slash or tilde in the keys it names', () {
        expect(
          () => parse('---\n"a/b~c":\n  2: x\n---\n'),
          throwsParseException('#/a~1b~0c: key 2 must be a string'),
        );
      });

      test('rejects a non-string name, naming the field', () {
        expect(
          () => parse('---\nname: 2\n---\n'),
          throwsParseException(contains('#/name')),
        );
      });

      test('rejects skills that are neither a list nor a string', () {
        expect(
          () => parse('---\nskills: 2\n---\n'),
          throwsParseException(contains('#/skills')),
        );
      });

      test('converts nested structures to plain Dart collections', () {
        // Agents nest `hooks:` that no other harness reads back. loadYaml
        // returns YamlMap/YamlList, which downstream writers serialize
        // inconsistently, so the boundary normalizes them here.
        final frontmatter = parse(
          '---\nname: a\nhooks:\n  PreToolUse:\n    - matcher: "Bash"\n---\n',
        );

        expect(
          frontmatter.values['hooks'],
          allOf(
            isA<Map<String, Object?>>(),
            isNot(isA<YamlMap>()),
            containsPair(
              'PreToolUse',
              allOf(isA<List<Object?>>(), isNot(isA<YamlList>()), [
                isA<Map<String, Object?>>().having(
                  (m) => m['matcher'],
                  'matcher',
                  'Bash',
                ),
              ]),
            ),
          ),
        );
      });
    });

    group('description', () {
      test('flattens a literal block onto one line', () {
        final frontmatter = parse('---\ndescription: |\n  One.\n  Two.\n---\n');

        expect(frontmatter.description, equals('One. Two.'));
      });

      test('flattens a folded block onto one line', () {
        final frontmatter = parse('---\ndescription: >\n  One.\n  Two.\n---\n');

        expect(frontmatter.description, equals('One. Two.'));
      });

      test('is empty when absent', () {
        expect(parse('---\nname: a\n---\n').description, isEmpty);
      });
    });

    group('oneLine', () {
      test('flattens folded and literal text onto one line', () {
        expect(Frontmatter.oneLine('  One.\n  Two.\n'), equals('One. Two.'));
      });

      test('is null for null', () {
        expect(Frontmatter.oneLine(null), isNull);
      });
    });

    group('skills', () {
      test('parses an inline list', () {
        expect(parse('---\nskills: [a, b]\n---\n').skills, equals(['a', 'b']));
      });

      test('parses a block sequence', () {
        expect(
          parse('---\nskills:\n  - a\n  - b\n---\n').skills,
          equals(['a', 'b']),
        );
      });

      test('splits a comma-separated string', () {
        expect(parse('---\nskills: a, b\n---\n').skills, equals(['a', 'b']));
      });

      test('parses a bare scalar as one entry', () {
        expect(parse('---\nskills: a\n---\n').skills, equals(['a']));
      });

      test('is empty when absent', () {
        expect(parse('---\nname: a\n---\n').skills, isEmpty);
      });

      test('drops blank entries', () {
        expect(
          parse('---\nskills: [a, "", b]\n---\n').skills,
          equals(['a', 'b']),
        );
      });
    });

    // allowed-tools and user-invocable are Claude-specific interpretations and
    // live in ClaudePluginParser; their tests are in
    // parser/claude_plugin_parser_test.dart.

    group('name', () {
      test('is null when absent', () {
        expect(parse('---\ndescription: a\n---\n').name, isNull);
      });
    });

    group('render', () {
      /// Renders then parses, so every case proves the two agree rather than
      /// asserting on a formatting choice that could drift.
      Frontmatter roundTrip(Map<String, Object?> values) =>
          parse('${Frontmatter.render(values)}\nbody\n');

      test('renders nothing for an empty map', () {
        // An empty fence is not a valid frontmatter block, so emit no block.
        expect(Frontmatter.render(const {}), isEmpty);
      });

      test('round-trips a plain string', () {
        expect(
          roundTrip({'name': 'testing'}).values['name'],
          equals('testing'),
        );
      });

      test('round-trips a string carrying YAML indicator characters', () {
        const awkward = 'Use when: reviewing #code, [maybe] {always}';

        expect(
          roundTrip({'description': awkward}).values['description'],
          equals(awkward),
        );
      });

      test('round-trips a string that looks like a bool', () {
        // Emitted plain, `yes` parses back as a boolean rather than a string.
        expect(roundTrip({'name': 'yes'}).values['name'], equals('yes'));
      });

      test('round-trips a string that looks like a number', () {
        expect(roundTrip({'name': '1.0'}).values['name'], equals('1.0'));
      });

      test('round-trips a string containing a quote and a backslash', () {
        const awkward = r'He said "run C:\dart" loudly';

        expect(roundTrip({'name': awkward}).values['name'], equals(awkward));
      });

      test('round-trips a multi-line string as a literal block', () {
        // The plugins write descriptions as folded and literal block scalars.
        const multi = 'First line.\nSecond line.';

        final rendered = Frontmatter.render({'description': multi});

        expect(rendered, contains('|2-'));
        expect(
          roundTrip({'description': multi}).values['description'],
          equals(multi),
        );
      });

      test('round-trips a multi-line string whose first line is indented', () {
        const indented = '  indented first\nthen flush';

        expect(
          roundTrip({'description': indented}).values['description'],
          equals(indented),
        );
      });

      test('round-trips a multi-line string inside a list', () {
        const multi = 'First line.\nSecond line.';

        expect(
          roundTrip({
            'notes': [multi, 'single'],
          }).values['notes'],
          equals([multi, 'single']),
        );
      });

      test('round-trips a multi-line string inside a nested map', () {
        const multi = '  First line.\nSecond line.';

        expect(
          roundTrip({
            'outer': {'inner': multi},
          }).values['outer'],
          equals({'inner': multi}),
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
        expect(roundTrip({'name': 'a\tb'}).values['name'], equals('a\tb'));
      });

      test('round-trips a list', () {
        expect(
          roundTrip({
            'keywords': ['a', 'b'],
          }).values['keywords'],
          equals(['a', 'b']),
        );
      });

      test('round-trips a nested map', () {
        final parsed = roundTrip({
          'metadata': {'type': 'reference', 'level': 2},
        });

        expect(
          parsed.values['metadata'],
          equals({'type': 'reference', 'level': 2}),
        );
        expect(parsed.values['metadata'], isA<Map<String, Object?>>());
      });

      test('round-trips a bool and a number', () {
        final parsed = roundTrip({'enabled': true, 'weight': 3});

        expect(parsed.values['enabled'], isTrue);
        expect(parsed.values['weight'], equals(3));
      });

      test('renders a null as an empty value', () {
        expect(roundTrip({'license': null}).values['license'], isNull);
      });

      test('renders an empty list and map as quoted scalars', () {
        // Neither has a useful block form; stringifying keeps the document
        // parseable instead of emitting a dangling key.
        final parsed = roundTrip({'a': <String>[], 'b': <String, Object?>{}});

        expect(parsed.values['a'], equals('[]'));
        expect(parsed.values['b'], equals('{}'));
      });

      test('round-trips the body beneath it', () {
        final rendered = Frontmatter.render({'name': 'a'});

        expect(parse('$rendered\n# Body\n').body, equals('# Body\n'));
      });
    });
  });
}
