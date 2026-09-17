import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/plugins.dart';

const _source = PluginSource(
  repo: 'https://github.com/example/sample-plugin',
  ref: 'v0.1.0',
);

void main() {
  const parser = PluginParser();

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('plugin_parser_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Writes [contents] to [relativePath] inside the temp plugin directory.
  void write(String relativePath, String contents) {
    File(p.join(temp.path, relativePath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  void writeMetadata([String json = '{"name": "temp-plugin"}']) {
    write(p.join('.claude-plugin', 'plugin.json'), json);
  }

  void writeAgent(String relativePath, {String name = 'a', String extra = ''}) {
    write(
      p.join('agents', relativePath),
      '---\nname: $name\n$extra---\n\nbody\n',
    );
  }

  ParsedPlugin parseTemp() => parser.parsePlugin(temp, source: _source);

  group('PluginParser', () {
    group('fixture', () {
      test('parses the sample plugin byte-equal to the golden manifest', () {
        final manifest = parser.parseAll([
          (
            directory: Directory('test/fixtures/sample_plugin'),
            source: _source,
          ),
        ]);

        final golden = File('test/fixtures/sample_plugin_manifest.json')
            .readAsStringSync();

        expect(manifest.toJsonString(), golden);
      });

      test('carries model values verbatim, including inherit', () {
        final plugin = parser.parsePlugin(
          Directory('test/fixtures/sample_plugin'),
          source: _source,
        );

        final models = {for (final a in plugin.agents) a.id: a.model};

        expect(models['flat-agent'], 'inherit');
        expect(models['nested/deep-agent'], 'sonnet');
      });

      test('gives a nested agent a forward-slashed id on every platform', () {
        final plugin = parser.parsePlugin(
          Directory('test/fixtures/sample_plugin'),
          source: _source,
        );

        expect(plugin.agents.map((a) => a.id), contains('nested/deep-agent'));
        expect(plugin.agents.every((a) => !a.id.contains(r'\')), isTrue);
      });

      test('preserves markdown rules inside an agent body', () {
        final plugin = parser.parsePlugin(
          Directory('test/fixtures/sample_plugin'),
          source: _source,
        );
        final deep = plugin.agents.firstWhere(
          (a) => a.id == 'nested/deep-agent',
        );

        expect('---'.allMatches(deep.body).length, 2);
        expect(deep.body, endsWith('rather than the last.'));
      });

      test('preserves a nested hooks map under extra', () {
        final plugin = parser.parsePlugin(
          Directory('test/fixtures/sample_plugin'),
          source: _source,
        );
        final flat = plugin.agents.firstWhere((a) => a.id == 'flat-agent');

        expect(flat.extra['hooks'], isA<Map<String, dynamic>>());
        expect(flat.tools, ['Read', 'Glob', 'Bash']);
      });

      test('keeps unknown plugin.json keys and a missing license', () {
        final plugin = parser.parsePlugin(
          Directory('test/fixtures/sample_plugin'),
          source: _source,
        );

        expect(plugin.metadata.license, isNull);
        expect(
          plugin.metadata.extra['experimental'],
          isA<Map<String, dynamic>>(),
        );
        expect(plugin.metadata.keywords, ['fixture', 'sample']);
      });
    });

    group('parseAll', () {
      test('combines several plugins into one manifest', () {
        writeMetadata();
        writeAgent('one.md');

        final manifest = parser.parseAll([
          (
            directory: Directory('test/fixtures/sample_plugin'),
            source: _source,
          ),
          (directory: temp, source: _source),
        ]);

        expect(manifest.plugins, hasLength(2));
        expect(manifest.plugins.map((p) => p.metadata.name).toList(), [
          'sample-plugin',
          'temp-plugin',
        ]);
      });
    });

    group('metadata failures', () {
      test('throws MissingPluginMetadata when plugin.json is absent', () {
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<MissingPluginMetadata>()));
      });

      test('throws InvalidPluginMetadata on malformed JSON', () {
        writeMetadata('{not json');
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<InvalidPluginMetadata>()));
      });

      test('throws InvalidPluginMetadata when the root is not an object', () {
        writeMetadata('["a"]');
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<InvalidPluginMetadata>()));
      });

      test('throws InvalidPluginMetadata when name is missing', () {
        writeMetadata('{"version": "1.0.0"}');
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<InvalidPluginMetadata>()));
      });

      test('throws InvalidPluginMetadata when name is empty', () {
        writeMetadata('{"name": ""}');
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<InvalidPluginMetadata>()));
      });

      test('throws InvalidPluginMetadata when name is not a string', () {
        writeMetadata('{"name": 7}');
        writeAgent('one.md');

        expect(parseTemp, throwsA(isA<InvalidPluginMetadata>()));
      });

      test('stringifies non-string scalar fields rather than dropping', () {
        writeMetadata('{"name": "p", "version": 3}');
        writeAgent('one.md');

        expect(parseTemp().metadata.version, '3');
      });
    });

    group('agent discovery failures', () {
      test('throws NoAgentsFound when agents/ is absent', () {
        writeMetadata();

        expect(parseTemp, throwsA(isA<NoAgentsFound>()));
      });

      test('throws NoAgentsFound when agents/ holds no markdown', () {
        writeMetadata();
        write(p.join('agents', 'README.txt'), 'not an agent');

        expect(parseTemp, throwsA(isA<NoAgentsFound>()));
      });

      test('keeps the same stem in different folders as distinct ids', () {
        writeMetadata();
        writeAgent('dup.md', name: 'first');
        writeAgent(p.join('nested', 'dup.md'), name: 'second');

        expect(parseTemp().agents.map((a) => a.id).toList(), [
          'dup',
          'nested/dup',
        ]);
      });

      test('picks up .MD as well as .md', () {
        writeMetadata();
        write(p.join('agents', 'upper.MD'), '---\nname: upper\n---\n\nbody\n');

        expect(parseTemp().agents.single.id, 'upper');
      });
    });

    group('agent failures', () {
      test('throws InvalidAgent when frontmatter is missing', () {
        writeMetadata();
        write(p.join('agents', 'bare.md'), '# No frontmatter here\n');

        expect(parseTemp, throwsA(isA<InvalidAgent>()));
      });

      test('throws InvalidAgent when name is missing', () {
        writeMetadata();
        write(p.join('agents', 'a.md'), '---\nmodel: sonnet\n---\n\nbody\n');

        expect(parseTemp, throwsA(isA<InvalidAgent>()));
      });

      test('throws InvalidAgent when name is empty', () {
        writeMetadata();
        write(p.join('agents', 'a.md'), '---\nname: ""\n---\n\nbody\n');

        expect(parseTemp, throwsA(isA<InvalidAgent>()));
      });

      test('throws InvalidAgent on malformed YAML frontmatter', () {
        writeMetadata();
        write(p.join('agents', 'a.md'), '---\nname: [unclosed\n---\n\nbody\n');

        expect(parseTemp, throwsA(isA<InvalidAgent>()));
      });

      test('throws InvalidAgent when frontmatter is not a mapping', () {
        writeMetadata();
        write(p.join('agents', 'a.md'), '---\n- one\n---\n\nbody\n');

        expect(parseTemp, throwsA(isA<InvalidAgent>()));
      });

      test('defaults a missing description to empty', () {
        writeMetadata();
        writeAgent('a.md');

        expect(parseTemp().agents.single.description, isEmpty);
      });
    });

    group('resolveAgentIds', () {
      test('strips the extension and forward-slashes nested paths', () {
        final agents = Directory(p.join('root', 'agents'));
        final ids = PluginParser.resolveAgentIds([
          File(p.join('root', 'agents', 'flat.md')),
          File(p.join('root', 'agents', 'nested', 'deep.md')),
        ], agents);

        expect(ids.keys.toList(), ['flat', 'nested/deep']);
      });

      test('throws DuplicateAgentId when two files resolve to one id', () {
        final agents = Directory(p.join('root', 'agents'));

        expect(
          () => PluginParser.resolveAgentIds([
            File(p.join('root', 'agents', 'dup.md')),
            File(p.join('root', 'agents', 'dup.MD')),
          ], agents),
          throwsA(
            isA<DuplicateAgentId>().having(
              (e) => e.message,
              'message',
              allOf(contains('dup'), contains('already produced by')),
            ),
          ),
        );
      });
    });

    test('throws UnreadableFile on non-UTF8 bytes', () {
      writeMetadata();
      File(p.join(temp.path, 'agents', 'bad.md'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0xC3, 0x28, 0xA0, 0xA1]);

      expect(parseTemp, throwsA(isA<UnreadableFile>()));
    });
  });
}
