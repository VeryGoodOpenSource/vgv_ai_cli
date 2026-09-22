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

  PlannedChange change(File target, String contents, ChangeMode mode) {
    return PlannedChange(file: target, contents: contents, mode: mode);
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

      test('overwrites an existing file wholesale', () {
        final target = seed('.agents/skills/a/SKILL.md', 'old');
        final applied = Reconciler(logger: logger)
            .apply([change(target, 'new', ChangeMode.own)]);

        expect(applied.single.outcome, ChangeOutcome.updated);
        expect(target.readAsStringSync(), 'new');
      });

      test('reports unchanged when content already matches', () {
        final target = seed('.agents/skills/a/SKILL.md', 'body');
        final applied = Reconciler(logger: logger)
            .apply([change(target, 'body', ChangeMode.own)]);

        expect(applied.single.outcome, ChangeOutcome.unchanged);
      });
    });

    group('mergeJson', () {
      test('writes incoming content into an empty target', () {
        final target = seed('.claude/settings.json', '   ');

        Reconciler(logger: logger).apply([
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ]);

        expect(jsonDecode(target.readAsStringSync()), {'a': 1});
      });

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
        verify(() => logger.warn(any())).called(1);
      });

      test('leaves the file alone when the existing root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode([1, 2, 3]));

        Reconciler(logger: logger).apply([
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ]);

        expect(jsonDecode(target.readAsStringSync()), [1, 2, 3]);
      });

      test('leaves the file alone when the incoming root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        Reconciler(logger: logger).apply([
          change(target, jsonEncode([1, 2]), ChangeMode.mergeJson),
        ]);

        expect(jsonDecode(target.readAsStringSync()), {'a': 1});
      });

      test('dedupes list entries that are objects', () {
        final target = seed('.claude/settings.json', '');
        const hooks = {
          'hooks': {
            'PostToolUse': [
              {
                'matcher': 'Edit',
                'hooks': [
                  {'type': 'command', 'command': 'dart format'},
                ],
              },
            ],
          },
        };

        final reconciler = Reconciler(logger: logger);
        final planned = [
          change(target, jsonEncode(hooks), ChangeMode.mergeJson),
        ];
        reconciler.apply(planned);
        final second = reconciler.apply(planned);

        final result =
            jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
        expect(
          ((result['hooks'] as Map)['PostToolUse'] as List).length,
          1,
          reason: 'an object entry must not be re-appended on every install',
        );
        expect(second.single.outcome, ChangeOutcome.unchanged);
      });

      test('keeps an explicit null the user wrote', () {
        // Seeded in the shape the reconciler writes, so the only thing that
        // could change the file is the merge itself.
        final target = seed('.claude/settings.json', '{\n  "model": null\n}\n');

        final applied = Reconciler(logger: logger).apply([
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
        ]);

        expect(
          (jsonDecode(target.readAsStringSync()) as Map)['model'],
          isNull,
          reason: 'an explicit null is a choice, not an absent key',
        );
        expect(applied.single.outcome, ChangeOutcome.skipped);
      });

      test('overrides an explicit null when forced', () {
        final target = seed('.claude/settings.json', '{"model": null}');

        Reconciler(logger: logger, force: true).apply([
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
        ]);

        expect((jsonDecode(target.readAsStringSync()) as Map)['model'], 'opus');
      });

      test('leaves the file alone when the incoming JSON is unparseable', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        final applied = Reconciler(logger: logger)
            .apply([change(target, '{ not json', ChangeMode.mergeJson)]);

        expect(jsonDecode(target.readAsStringSync()), {'a': 1});
        expect(applied.single.outcome, ChangeOutcome.skipped);
        verify(() => logger.warn(any())).called(1);
      });

      test('creates nothing when the incoming JSON is unparseable', () {
        final target = file('.claude/settings.json');

        final applied = Reconciler(logger: logger)
            .apply([change(target, '{ not json', ChangeMode.mergeJson)]);

        expect(target.existsSync(), isFalse);
        expect(applied.single.outcome, ChangeOutcome.skipped);
      });

      test('recurses into nested maps', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({
            'nested': {'kept': 1},
          }),
        );

        Reconciler(logger: logger).apply([
          change(
            target,
            jsonEncode({
              'nested': {'added': 2},
            }),
            ChangeMode.mergeJson,
          ),
        ]);

        final result =
            jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
        expect(result['nested'], {'kept': 1, 'added': 2});
      });
    });

    group('mergeToml', () {
      test('writes incoming content into an empty target', () {
        final target = seed('.codex/config.toml', '');

        Reconciler(logger: logger).apply([
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        ]);

        expect(
          target.readAsStringSync(),
          '[mcp_servers.dart]\ncommand = "dart"\n',
        );
      });

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

      test('appends after a file with no trailing newline', () {
        final target = seed('.codex/config.toml', 'model = "gpt"');

        Reconciler(logger: logger).apply([
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        ]);

        final result = target.readAsStringSync();
        expect(result, startsWith('model = "gpt"\n\n'));
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

      test('ignores an empty incoming fragment', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger)
            .apply([change(target, '   ', ChangeMode.mergeToml)]);

        expect(target.readAsStringSync(), 'model = "gpt"\n');
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

      test('skips a fragment with no table header', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger)
            .apply([change(target, 'loose = "value"', ChangeMode.mergeToml)]);

        expect(target.readAsStringSync(), 'model = "gpt"\n');
      });

      test('appends an array-of-table whose header is absent', () {
        final target = seed('.codex/config.toml', '[[server]]\nname = "a"\n');

        Reconciler(logger: logger).apply([
          change(target, '[[client]]\nname = "b"', ChangeMode.mergeToml),
        ]);

        final result = target.readAsStringSync();
        expect(result, contains('name = "a"'));
        expect(result, contains('[[client]]'));
      });

      test('appends tables written back to back in one fragment', () {
        final target = seed('.codex/config.toml', '[mcp_servers.a]\nx = 1\n');

        Reconciler(logger: logger).apply([
          change(
            target,
            '[mcp_servers.a]\nx = 1\n[mcp_servers.b]\ny = 2',
            ChangeMode.mergeToml,
          ),
        ]);

        final result = target.readAsStringSync();
        expect(result, contains('[mcp_servers.b]'));
        expect(
          '[mcp_servers.a]'.allMatches(result).length,
          1,
          reason: 'a duplicate table header is a TOML parse error',
        );
      });

      test('keeps the comment written above a table', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger).apply([
          change(
            target,
            '# Generated by VGV.\n[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        ]);

        final result = target.readAsStringSync();
        expect(result, contains('# Generated by VGV.'));
        expect(result, contains('[mcp_servers.dart]'));
      });

      test('leaves a comment with the table it introduces', () {
        final target = seed('.codex/config.toml', '[a]\nx = 1\n');

        Reconciler(logger: logger).apply([
          change(
            target,
            '[a]\nx = 1\n\n# About b.\n[b]\ny = 2',
            ChangeMode.mergeToml,
          ),
        ]);

        final result = target.readAsStringSync();
        expect(result, contains('# About b.'));
        expect('x = 1'.allMatches(result).length, 1);
      });

      test('reports skipped when it declines to touch a table', () {
        final target = seed('.codex/config.toml', '[a]\nx = "mine"\n');

        final applied = Reconciler(logger: logger)
            .apply([change(target, '[a]\nx = "ours"', ChangeMode.mergeToml)]);

        expect(applied.single.outcome, ChangeOutcome.skipped);
      });

      test(
        'leaves a same-named array-of-table alone (table-granular limit)',
        () {
          // Table-granular merge sees `[[server]]` as the table `[server`, so a
          // second one with the same header is treated as already present and
          // left untouched rather than duplicated.
          final target = seed('.codex/config.toml', '[[server]]\nname = "a"\n');

          Reconciler(logger: logger).apply([
            change(target, '[[server]]\nname = "b"', ChangeMode.mergeToml),
          ]);

          final result = target.readAsStringSync();
          expect(result, contains('name = "a"'));
          expect(result, isNot(contains('name = "b"')));
        },
      );
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

    group('writes', () {
      test('leaves no temporary file behind', () {
        final target = file('.claude/settings.json');

        Reconciler(logger: logger).apply([
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ]);

        expect(target.parent.listSync().map((e) => e.path), [
          target.path,
        ], reason: 'the write goes through a sibling temp file and renames it');
      });
    });

    group('idempotency', () {
      test('a second apply of the same changes is all unchanged', () {
        final json = seed('.claude/settings.json', jsonEncode({'model': 'x'}));
        final toml = seed('.codex/config.toml', 'model = "gpt"\n');
        final skill = file('.agents/skills/a/SKILL.md');

        final changes = [
          change(
            json,
            jsonEncode({
              'enabled': true,
              'hooks': [
                {'type': 'command'},
              ],
            }),
            ChangeMode.mergeJson,
          ),
          change(
            toml,
            '[mcp.dart]\ncommand = "dart"\n[mcp.gh]\ncommand = "gh"',
            ChangeMode.mergeToml,
          ),
          change(skill, 'body', ChangeMode.own),
        ];

        final reconciler = Reconciler(logger: logger)..apply(changes);
        final second = reconciler.apply(changes);

        expect(
          second.map((a) => a.outcome),
          everyElement(ChangeOutcome.unchanged),
        );
      });
    });
  });
}
