import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/skills_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';

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
          mcpServers: const [],
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

    test('remembers the file each bundled copy came from', () {
      final result = translate([
        skill('review', files: {'scripts/scope.sh': 'echo\n'}),
      ]);

      expect(
        changeAt(result, 'review/scripts/scope.sh').source?.path,
        '/plugins/wingspan/skills/review/scripts/scope.sh',
      );
    });

    test('copies a file that is not UTF-8 byte for byte', () {
      final review = skill('review');
      final bytes = [0x89, 0x50, 0x4e, 0x47, 0xff, 0xfe];
      review.directory.childFile('logo.png').writeAsBytesSync(bytes);

      final result = translate([review]);

      expect(changeAt(result, 'review/logo.png').bytes, bytes);
    });

    group('CLAUDE_SKILL_DIR', () {
      const variable = r'${CLAUDE_SKILL_DIR}';
      const target = '/home/dev/.agents/skills/review';

      test('is spelled out in SKILL.md as the copy it lands in', () {
        final result = translate([
          skill('review', body: 'Run $variable/scripts/scope.sh\n'),
        ]);

        expect(
          changeAt(result, 'review/SKILL.md').contents,
          contains('Run $target/scripts/scope.sh'),
        );
      });

      test('is spelled out in a bundled text file', () {
        final result = translate([
          skill('review', files: {'reference.md': 'See $variable/a.md\n'}),
        ]);

        expect(
          changeAt(result, 'review/reference.md').contents,
          'See $target/a.md\n',
        );
      });
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

    group('MCP tool names', () {
      test('are copied untouched, frontmatter included', () {
        // Rewriting them to CLI commands once put backticked commands into
        // `allowed-tools`, an invalid allowlist on every harness that reads
        // the Agent Skills spec.
        final result = translate([
          skill(
            'testing',
            frontmatter: {
              'name': 'testing',
              'allowed-tools': 'Bash mcp__dart__analyze_files',
            },
            body: 'Run mcp__dart__analyze_files.\n',
          ),
        ]);

        final document = changeAt(result, 'testing/SKILL.md').contents;
        expect(
          document,
          contains('allowed-tools: "Bash mcp__dart__analyze_files"'),
        );
        expect(document, contains('Run mcp__dart__analyze_files.'));
        expect(result.notes, isEmpty);
      });

      test('are copied untouched in reference files', () {
        final result = translate([
          skill('testing', files: {'references/a.md': 'mcp__dart__pub here\n'}),
        ]);

        expect(
          changeAt(result, 'references/a.md').contents,
          'mcp__dart__pub here\n',
        );
      });
    });
  });
}
