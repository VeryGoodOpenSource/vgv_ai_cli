import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/frontmatter.dart';
import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';

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

    test('passes nested structures through untouched', () {
      // Agents nest `hooks:` that no other harness reads back.
      final frontmatter = _parse(
        '---\nname: a\nhooks:\n  PreToolUse:\n    - matcher: "Bash"\n---\n',
      );

      expect(frontmatter.values['hooks'], isNotNull);
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

  group('allowedTools', () {
    test('splits on spaces', () {
      expect(_parse('---\nallowed-tools: Read Glob\n---\n').allowedTools, [
        'Read',
        'Glob',
      ]);
    });

    test('splits on commas', () {
      // Only `animations` writes it this way.
      expect(_parse('---\nallowed-tools: Read,Glob\n---\n').allowedTools, [
        'Read',
        'Glob',
      ]);
    });

    test('splits on a mix of both', () {
      expect(
        _parse('---\nallowed-tools: Read, Glob  Grep\n---\n').allowedTools,
        ['Read', 'Glob', 'Grep'],
      );
    });

    test('falls back to tools', () {
      expect(_parse('---\ntools: Read, Glob\n---\n').allowedTools, [
        'Read',
        'Glob',
      ]);
    });

    test('is empty when absent', () {
      expect(_parse('---\nname: a\n---\n').allowedTools, isEmpty);
    });
  });

  group('userInvocable', () {
    test('is true when absent', () {
      // The Flutter plugin omits the key on all 16 of its skills.
      expect(_parse('---\nname: a\n---\n').userInvocable, isTrue);
    });

    test('is true when explicitly true', () {
      expect(_parse('---\nuser-invocable: true\n---\n').userInvocable, isTrue);
    });

    test('is false when explicitly false', () {
      expect(
        _parse('---\nuser-invocable: false\n---\n').userInvocable,
        isFalse,
      );
    });
  });

  group('name', () {
    test('is null when absent', () {
      expect(_parse('---\ndescription: a\n---\n').name, isNull);
    });
  });
}
