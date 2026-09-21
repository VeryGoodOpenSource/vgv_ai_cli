import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/frontmatter.dart';
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

    test('keeps a non-string key as a string', () {
      expect(_parse('---\n2: x\n---\n').values.keys, contains('2'));
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

  group('skills', () {
    test('parses an inline list', () {
      expect(_parse('---\nskills: [a, b]\n---\n').skills, ['a', 'b']);
    });

    test('parses a block sequence', () {
      expect(_parse('---\nskills:\n  - a\n  - b\n---\n').skills, ['a', 'b']);
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
  // now live in ClaudePluginParser; their tests moved to
  // parser/claude_plugin_parser_test.dart.

  group('name', () {
    test('is null when absent', () {
      expect(_parse('---\ndescription: a\n---\n').name, isNull);
    });
  });

  group('PluginParseException', () {
    test('is not a FormatException', () {
      // The command runner catches FormatException and renders it as a CLI
      // usage error. YamlException and jsonDecode both throw FormatException,
      // so a corrupt plugin file must not be one.
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
