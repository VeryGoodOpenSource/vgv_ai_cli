import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/skills_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  /// Builds a skill directory and the [SkillAsset] that points at it.
  SkillAsset skill(
    String name, {
    String body = '# Body\n',
    Map<String, Object?>? frontmatter,
    Map<String, String> files = const {},
  }) {
    final directory = fs.directory('/plugins/wingspan/skills/$name')
      ..createSync(recursive: true);
    directory.childFile('SKILL.md').writeAsStringSync('---\n---\n$body');
    for (final MapEntry(:key, :value) in files.entries) {
      fs.file(p.join(directory.path, key))
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return SkillAsset(
      name: name,
      description: 'the $name skill',
      body: body,
      userInvocable: true,
      allowedTools: const [],
      portableFrontmatter: frontmatter ?? {'name': name},
      directory: directory,
    );
  }

  TranslationResult translate(List<SkillAsset> skills) =>
      const SkillsTranslator().translate(
        assets: PluginAssets(
          skills: skills,
          agents: const [],
          mcpServers: const {},
        ),
        home: home,
      );

  PlannedChange changeAt(TranslationResult result, String suffix) =>
      result.changes.firstWhere((c) => c.file.path.endsWith(suffix));

  group('SkillsTranslator', () {
    test('plans one SKILL.md per skill under ~/.agents/skills', () {
      final result = translate([skill('testing'), skill('bloc')]);

      expect(
        result.changes.map((c) => c.file.path),
        containsAll([
          '/home/dev/.agents/skills/testing/SKILL.md',
          '/home/dev/.agents/skills/bloc/SKILL.md',
        ]),
      );
    });

    test('writes the skills once, not once per harness', () {
      final result = translate([skill('testing')]);

      expect(
        result.changes.where((c) => c.file.path.endsWith('SKILL.md')),
        hasLength(1),
      );
    });

    test('leaves the shared copy owned by no harness', () {
      // Four harnesses read this one copy, so it belongs to none of them.
      expect(
        translate([skill('testing')]).changes.every((c) => c.harness == null),
        isTrue,
      );
    });

    test('owns the files it writes, so a rerun rewrites them wholesale', () {
      expect(
        translate([skill('testing')]).changes
            .every((c) => c.mode == ChangeMode.own),
        isTrue,
      );
    });

    test('rebuilds SKILL.md so its frontmatter parses back', () {
      final result = translate([
        skill(
          'testing',
          body: '# Testing\n',
          frontmatter: {'name': 'testing', 'description': 'Dart tests.'},
        ),
      ]);

      final parsed = Frontmatter.parse(
        changeAt(result, 'testing/SKILL.md').contents,
        path: 'SKILL.md',
      );

      expect(parsed.name, 'testing');
      expect(parsed.description, 'Dart tests.');
      expect(parsed.body, contains('# Testing'));
    });

    test('carries the files a skill ships alongside it', () {
      final result = translate([
        skill('testing', files: {'references/matchers.md': '# Matchers\n'}),
      ]);

      expect(
        changeAt(result, 'testing/references/matchers.md').contents,
        '# Matchers\n',
      );
    });

    test('does not copy the source SKILL.md over the rebuilt one', () {
      final result = translate([skill('testing')]);

      expect(
        result.changes.where((c) => c.file.path.endsWith('SKILL.md')),
        hasLength(1),
      );
    });

    test('reports a skill whose directory has gone away', () {
      // The parser only builds a skill from a directory holding a SKILL.md, so
      // this means the plugin cache was cleared between resolution and
      // translation. It should report, not throw out of install.
      final asset = skill('testing');
      asset.directory.deleteSync(recursive: true);

      final result = translate([asset]);

      expect(result.notes.single.subject, 'testing');
      expect(result.notes.single.reason, contains('has gone away'));
      expect(changeAt(result, 'testing/SKILL.md').contents, isNotEmpty);
    });

    group('symlinks', () {
      test('materializes a link into the pooled shared directory', () {
        // Wingspan pools references under skills/shared and symlinks them in.
        // skills/shared is not a skill and is never copied, so an unresolved
        // link would land broken.
        final asset = skill('build');
        fs.file('/plugins/wingspan/skills/shared/references/pooled.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('# Pooled\n');
        fs.link(p.join(asset.directory.path, 'references', 'pooled.md'))
          ..parent.createSync(recursive: true)
          ..createSync('/plugins/wingspan/skills/shared/references/pooled.md');

        final result = translate([asset]);

        expect(
          changeAt(result, 'build/references/pooled.md').contents,
          '# Pooled\n',
        );
        expect(result.notes, isEmpty);
      });

      test('materializes a link with a relative target', () {
        final asset = skill('build');
        fs.file('/plugins/wingspan/skills/shared/references/rel.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('# Relative\n');
        fs.link(p.join(asset.directory.path, 'references', 'rel.md'))
          ..parent.createSync(recursive: true)
          ..createSync('../../shared/references/rel.md');

        final result = translate([asset]);

        expect(
          changeAt(result, 'build/references/rel.md').contents,
          '# Relative\n',
        );
      });

      test('reports a link whose target does not exist', () {
        final asset = skill('build');
        fs.link(p.join(asset.directory.path, 'references', 'gone.md'))
          ..parent.createSync(recursive: true)
          ..createSync('/plugins/wingspan/skills/shared/gone.md');

        final result = translate([asset]);

        expect(
          result.notes,
          contains(
            const TranslationNote(
              subject: 'build/references/gone.md',
              reason: 'the symlink points at something that does not exist',
            ),
          ),
        );
        expect(
          result.changes.map((c) => c.file.path),
          isNot(contains(endsWith('gone.md'))),
        );
      });

      test('reports a link to a directory rather than walking it', () {
        // followLinks is off so a cycle cannot hang the walk.
        final asset = skill('build');
        fs
            .directory('/plugins/wingspan/skills/shared/references')
            .createSync(recursive: true);
        fs.link(p.join(asset.directory.path, 'references'))
          ..parent.createSync(recursive: true)
          ..createSync('/plugins/wingspan/skills/shared/references');

        final result = translate([asset]);

        expect(
          result.notes.single.reason,
          'the symlink points at a directory, which is not copied',
        );
      });
    });

    group('MCP rewriting', () {
      test('rewrites tool names in the skill body', () {
        final result = translate([
          skill('testing', body: 'Run mcp__dart__analyze_files.\n'),
        ]);

        expect(
          changeAt(result, 'testing/SKILL.md').contents,
          contains('`dart analyze`'),
        );
      });

      test('rewrites tool names in the frontmatter', () {
        final result = translate([
          skill(
            'testing',
            frontmatter: {
              'name': 'testing',
              'allowed-tools': 'mcp__dart__analyze_files',
            },
          ),
        ]);

        expect(
          changeAt(result, 'testing/SKILL.md').contents,
          contains('`dart analyze`'),
        );
      });

      test('rewrites tool names in markdown references', () {
        final result = translate([
          skill('testing', files: {'references/a.md': 'mcp__dart__pub here\n'}),
        ]);

        expect(
          changeAt(result, 'references/a.md').contents,
          '`dart pub` here\n',
        );
      });

      test('leaves shell scripts alone', () {
        // Rewriting a tool name inside a script would corrupt it.
        final result = translate([
          skill('rebase', files: {'scripts/run.sh': 'echo mcp__dart__pub\n'}),
        ]);

        expect(
          changeAt(result, 'scripts/run.sh').contents,
          'echo mcp__dart__pub\n',
        );
      });

      test('reports a reference with no CLI equivalent', () {
        final result = translate([
          skill('testing', body: 'Call mcp__unknown__thing.\n'),
        ]);

        expect(result.notes.single.subject, 'testing');
        expect(result.notes.single.reason, contains('mcp__unknown__thing'));
      });

      test('reports an unmapped reference found in a reference file', () {
        final result = translate([
          skill('testing', files: {'references/a.md': 'mcp__unknown__thing\n'}),
        ]);

        expect(result.notes.single.subject, 'testing/references/a.md');
      });

      test('reports nothing when every reference maps', () {
        final result = translate([
          skill('testing', body: 'Run mcp__dart__analyze_files.\n'),
        ]);

        expect(result.notes, isEmpty);
      });
    });
  });
}
