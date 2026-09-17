import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

class _MockLogger extends Mock implements Logger;

void main() {
  late Directory home;
  late Logger logger;

  setUp(() {
    home = Directory.systemTemp.createTempSync('vgv_home_');
    logger = _MockLogger();
  });

  tearDown(() => home.deleteSync(recursive: true));

  File file(String relative) => File('${home.path}/$relative');

  File seed(String relative, String contents) {
    final f = file(relative)..parent.createSync(recursive: true);
    return f..writeAsStringSync(contents);
  }

  PlannedChange change(
    File target,
    String contents,
    ChangeMode mode, {
    String harness = 'claude',
  }) {
    return PlannedChange(
      file: target,
      contents: contents,
      mode: mode,
      harness: harness,
    );
  }

  group('Reconciler', () {
    group('own', () {
      test('creates a file that did not exist', () {
        final target = file('.agents/skills/testing/SKILL.md');
        final applied = Reconciler(logger: logger)
            .apply([change(target, 'body', ChangeMode.own)]);

        expect(applied.single.outcome, ChangeOutcome.created);
        expect(target.readAsStringSync(), 'body');
      });

      test('reports unchanged when content already matches', () {
        final target = seed('.agents/skills/a/SKILL.md', 'body');
        final applied = Reconciler(logger: logger)
            .apply([change(target, 'body', ChangeMode.own)]);

        expect(applied.single.outcome, ChangeOutcome.unchanged);
        expect(applied.single.backup, isNull);
      });
    });

    group('mergeJson', () {
      test('preserves keys it knows nothing about', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({
            'model': 'opus',
            'permissions': {
              'allow': ['Bash(git *)'],
            },
          }),
        );

        Reconciler(logger: logger).apply([
          change(
            target,
            jsonEncode({'enabledPlugins': <String, bool>{}}),
            ChangeMode.mergeJson,
          ),
        ]);

        final result =
            jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
        expect(result['model'], 'opus');
        expect((result['permissions'] as Map)['allow'], ['Bash(git *)']);
        expect(result, contains('enabledPlugins'));
      });

      test('unions lists without duplicating entries', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({
            'permissions': {
              'allow': ['Bash(git *)', 'Read'],
            },
          }),
        );

        Reconciler(logger: logger).apply([
          change(
            target,
            jsonEncode({
              'permissions': {
                'allow': ['Read', 'Bash(dart *)'],
              },
            }),
            ChangeMode.mergeJson,
          ),
        ]);

        final result =
            jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
        expect((result['permissions'] as Map)['allow'], [
          'Bash(git *)',
          'Read',
          'Bash(dart *)',
        ]);
      });

      test('keeps the existing scalar on a conflict', () {
        final target = seed(
          '.gemini/settings.json',
          jsonEncode({'model': 'x'}),
        );

        Reconciler(logger: logger).apply([
          change(target, jsonEncode({'model': 'y'}), ChangeMode.mergeJson),
        ]);

        expect(
          (jsonDecode(target.readAsStringSync()) as Map)['model'],
          'x',
          reason: "the user's own model choice must survive an install",
        );
      });

      test('overrides the existing scalar when forced', () {
        final target = seed(
          '.gemini/settings.json',
          jsonEncode({'model': 'x'}),
        );

        Reconciler(logger: logger, force: true).apply([
          change(target, jsonEncode({'model': 'y'}), ChangeMode.mergeJson),
        ]);

        expect((jsonDecode(target.readAsStringSync()) as Map)['model'], 'y');
      });

      test('leaves an unparseable file alone rather than discarding it', () {
        final target = seed('.claude/settings.json', '{ not json');

        Reconciler(logger: logger).apply([
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ]);

        expect(target.readAsStringSync(), '{ not json');
      });

      test('backs up a file before modifying it', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({'model': 'x'}),
        );

        final applied = Reconciler(logger: logger).apply([
          change(target, jsonEncode({'other': 1}), ChangeMode.mergeJson),
        ]);

        final backup = applied.single.backup;
        expect(backup, isNotNull);
        expect(jsonDecode(backup!.readAsStringSync()), {'model': 'x'});
      });
    });

    group('block', () {
      const block = '$blockBegin\ngenerated\n$blockEnd';

      test('appends the block when the file has no markers', () {
        final target = seed('.claude/CLAUDE.md', '# My notes\n\nKeep me.\n');

        Reconciler(logger: logger)
            .apply([change(target, block, ChangeMode.block)]);

        final result = target.readAsStringSync();
        expect(result, startsWith('# My notes\n\nKeep me.\n'));
        expect(result, contains('generated'));
      });

      test('replaces only the block and preserves prose around it', () {
        final target = seed(
          '.claude/CLAUDE.md',
          'BEFORE\n\n$blockBegin\nold\n$blockEnd\n\nAFTER\n',
        );

        Reconciler(logger: logger)
            .apply([change(target, block, ChangeMode.block)]);

        final result = target.readAsStringSync();
        expect(result, startsWith('BEFORE\n\n'));
        expect(result, endsWith('\n\nAFTER\n'));
        expect(result, contains('generated'));
        expect(result, isNot(contains('old')));
      });

      test('is idempotent across repeated installs', () {
        final target = seed('.claude/CLAUDE.md', 'BEFORE\n');
        final reconciler = Reconciler(logger: logger)
          ..apply([change(target, block, ChangeMode.block)]);
        final first = target.readAsStringSync();

        final second = reconciler.apply([
          change(target, block, ChangeMode.block),
        ]);

        expect(target.readAsStringSync(), first);
        expect(second.single.outcome, ChangeOutcome.unchanged);
      });
    });

    group('mergeToml', () {
      test('appends a table that is not already present', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger).apply([
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        ]);

        final result = target.readAsStringSync();
        expect(result, contains('model = "gpt"'));
        expect(result, contains('[mcp_servers.dart]'));
      });

      test('leaves a table the user already wrote alone', () {
        final target = seed(
          '.codex/config.toml',
          '[mcp_servers.dart]\ncommand = "custom"\n',
        );

        Reconciler(logger: logger).apply([
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        ]);

        expect(target.readAsStringSync(), contains('command = "custom"'));
        expect(target.readAsStringSync(), isNot(contains('command = "dart"')));
      });

      test('ignores a comment-only fragment', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger).apply([
          change(
            target,
            '# No MCP servers were resolved.',
            ChangeMode.mergeToml,
          ),
        ]);

        expect(target.readAsStringSync(), 'model = "gpt"\n');
      });
    });

    group('dryRun', () {
      test('reports the change without touching disk', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({'model': 'x'}),
        );

        final applied = Reconciler(logger: logger, dryRun: true).apply([
          change(target, jsonEncode({'other': 1}), ChangeMode.mergeJson),
        ]);

        expect(applied.single.outcome, ChangeOutcome.updated);
        expect(jsonDecode(target.readAsStringSync()), {'model': 'x'});
        expect(applied.single.backup, isNull);
      });

      test('creates nothing for a new file', () {
        final target = file('.agents/skills/a/SKILL.md');

        final applied = Reconciler(
          logger: logger,
          dryRun: true,
        ).apply([change(target, 'body', ChangeMode.own)]);

        expect(applied.single.outcome, ChangeOutcome.created);
        expect(target.existsSync(), isFalse);
      });
    });
  });
}
