import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';
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

  File file(String relative) => File(p.join(home.path, relative));

  File seed(String relative, String contents) {
    final f = file(relative)..parent.createSync(recursive: true);
    return f..writeAsStringSync(contents);
  }

  PlannedChange change(File target, String contents, ChangeMode mode) {
    return switch (mode) {
      ChangeMode.own => PlannedChange.own(file: target, contents: contents),
      ChangeMode.mergeJson => PlannedChange.mergeJson(
        file: target,
        contents: contents,
      ),
      ChangeMode.mergeToml => PlannedChange.mergeToml(
        file: target,
        contents: contents,
      ),
    };
  }

  Map<String, dynamic> readJson(File target) =>
      jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;

  group('Reconciler', () {
    group('own', () {
      test('creates a file that did not exist', () {
        final target = file('.agents/skills/testing/SKILL.md');
        final applied = Reconciler(logger: logger)
            .apply(change(target, 'body', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.created);
        expect(target.readAsStringSync(), 'body');
      });

      test('overwrites an existing file wholesale', () {
        final target = seed('.agents/skills/a/SKILL.md', 'old');
        final applied = Reconciler(logger: logger)
            .apply(change(target, 'new', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.updated);
        expect(target.readAsStringSync(), 'new');
      });

      test('reports unchanged when content already matches', () {
        final target = seed('.agents/skills/a/SKILL.md', 'body');
        final applied = Reconciler(logger: logger)
            .apply(change(target, 'body', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.unchanged);
      });
    });

    group('mergeJson', () {
      test('writes incoming content into an empty target', () {
        final target = seed('.claude/settings.json', '   ');

        Reconciler(logger: logger)
            .apply(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

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

        Reconciler(logger: logger).apply(
          change(
            target,
            jsonEncode({'enabledPlugins': <String, bool>{}}),
            ChangeMode.mergeJson,
          ),
        );

        final result = readJson(target);
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

        Reconciler(logger: logger).apply(
          change(
            target,
            jsonEncode({
              'permissions': {
                'allow': ['Read', 'Bash(dart *)'],
              },
            }),
            ChangeMode.mergeJson,
          ),
        );

        final result = readJson(target);
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

        Reconciler(logger: logger).apply(
          change(target, jsonEncode({'model': 'y'}), ChangeMode.mergeJson),
        );

        expect(
          readJson(target)['model'],
          'x',
          reason: "the user's own model choice must survive an install",
        );
      });

      test('overrides the existing scalar when forced', () {
        final target = seed(
          '.gemini/settings.json',
          jsonEncode({'model': 'x'}),
        );

        Reconciler(logger: logger, force: true).apply(
          change(target, jsonEncode({'model': 'y'}), ChangeMode.mergeJson),
        );

        expect(readJson(target)['model'], 'y');
      });

      test('leaves an unparseable file alone rather than discarding it', () {
        final target = seed('.claude/settings.json', '{ not json');

        Reconciler(logger: logger)
            .apply(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

        expect(target.readAsStringSync(), '{ not json');
      });

      test('leaves the file alone when the existing root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode([1, 2, 3]));

        Reconciler(logger: logger)
            .apply(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

        expect(jsonDecode(target.readAsStringSync()), [1, 2, 3]);
      });

      test('leaves the file alone when the incoming root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        Reconciler(logger: logger)
            .apply(change(target, jsonEncode([1, 2]), ChangeMode.mergeJson));

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
        final planned = change(target, jsonEncode(hooks), ChangeMode.mergeJson);
        reconciler.apply(planned);
        final second = reconciler.apply(planned);

        final result = readJson(target);
        expect(
          ((result['hooks'] as Map)['PostToolUse'] as List).length,
          1,
          reason: 'an object entry must not be re-appended on every install',
        );
        expect(second.outcome, ChangeOutcome.unchanged);
      });

      test('keeps the formatting when the merge adds nothing', () {
        const formatted = '{\n    "model": "opus"\n}\n';
        final target = seed('.claude/settings.json', formatted);

        final applied = Reconciler(logger: logger).apply(
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
        );

        expect(
          target.readAsStringSync(),
          formatted,
          reason: "a no-op merge must not canonicalise the user's file",
        );
        expect(applied.outcome, ChangeOutcome.unchanged);
      });

      test('keeps an explicit null the user wrote', () {
        final target = seed('.claude/settings.json', '{"model": null}');

        final applied = Reconciler(logger: logger).apply(
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
        );

        expect(
          readJson(target)['model'],
          isNull,
          reason: 'an explicit null is a choice, not an absent key',
        );
        expect(applied.outcome, ChangeOutcome.skipped);
      });

      test('overrides an explicit null when forced', () {
        final target = seed('.claude/settings.json', '{"model": null}');

        Reconciler(logger: logger, force: true).apply(
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
        );

        expect(readJson(target)['model'], 'opus');
      });

      test('leaves the file alone when the incoming JSON is unparseable', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        final applied = Reconciler(logger: logger)
            .apply(change(target, '{ not json', ChangeMode.mergeJson));

        expect(jsonDecode(target.readAsStringSync()), {'a': 1});
        expect(applied.outcome, ChangeOutcome.skipped);
      });

      test('creates nothing when the incoming JSON is unparseable', () {
        final target = file('.claude/settings.json');

        final applied = Reconciler(logger: logger)
            .apply(change(target, '{ not json', ChangeMode.mergeJson));

        expect(target.existsSync(), isFalse);
        expect(applied.outcome, ChangeOutcome.skipped);
      });

      test('recurses into nested maps', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({
            'nested': {'kept': 1},
          }),
        );

        Reconciler(logger: logger).apply(
          change(
            target,
            jsonEncode({
              'nested': {'added': 2},
            }),
            ChangeMode.mergeJson,
          ),
        );

        final result = readJson(target);
        expect(result['nested'], {'kept': 1, 'added': 2});
      });
    });

    group('mergeToml', () {
      Map<String, dynamic> readToml(File target) =>
          TomlDocument.parse(target.readAsStringSync()).toMap();

      test('writes incoming content into an empty target', () {
        final target = seed('.codex/config.toml', '');

        Reconciler(logger: logger).apply(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect(readToml(target), {
          'mcp_servers': {
            'dart': {'command': 'dart'},
          },
        });
      });

      test('adds a table while keeping the existing one', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger).apply(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        final result = readToml(target);
        expect(result['model'], 'gpt');
        expect((result['mcp_servers'] as Map)['dart'], {'command': 'dart'});
      });

      test('adds a bare top-level key', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        Reconciler(logger: logger)
            .apply(change(target, 'loose = "value"', ChangeMode.mergeToml));

        final result = readToml(target);
        expect(result['model'], 'gpt');
        expect(result['loose'], 'value');
      });

      test('overwrites a value the user edited', () {
        final target = seed(
          '.codex/config.toml',
          '[mcp_servers.dart]\ncommand = "custom"\n',
        );

        final applied = Reconciler(logger: logger).apply(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect((readToml(target)['mcp_servers'] as Map)['dart'], {
          'command': 'dart',
        });
        expect(applied.outcome, ChangeOutcome.updated);
      });

      test('keeps unrelated keys the user added', () {
        final target = seed(
          '.codex/config.toml',
          '[mcp_servers.dart]\ncommand = "custom"\nextra = "mine"\n',
        );

        Reconciler(logger: logger).apply(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect((readToml(target)['mcp_servers'] as Map)['dart'], {
          'command': 'dart',
          'extra': 'mine',
        });
      });

      test('unions arrays of tables', () {
        final target = seed('.codex/config.toml', '[[server]]\nname = "a"\n');

        Reconciler(
          logger: logger,
        ).apply(change(target, '[[server]]\nname = "b"', ChangeMode.mergeToml));

        expect(readToml(target)['server'], [
          {'name': 'a'},
          {'name': 'b'},
        ]);
      });

      test('reports unchanged when the merge adds nothing', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        final applied = Reconciler(logger: logger).apply(
          change(
            target,
            '# No MCP servers were resolved.',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.unchanged);
        expect(readToml(target), {'model': 'gpt'});
      });

      test('leaves the file alone when the payload is malformed', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        final applied = Reconciler(logger: logger)
            .apply(change(target, '[unterminated', ChangeMode.mergeToml));

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(target.readAsStringSync(), 'model = "gpt"\n');
      });

      test('leaves the file alone when it cannot be parsed', () {
        final target = seed('.codex/config.toml', '[unterminated');

        final applied = Reconciler(logger: logger).apply(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(target.readAsStringSync(), '[unterminated');
      });
    });

    group('dryRun', () {
      test('reports the change without touching disk', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({'model': 'x'}),
        );

        final applied = Reconciler(
          logger: logger,
          dryRun: true,
        ).apply(change(target, jsonEncode({'other': 1}), ChangeMode.mergeJson));

        expect(applied.outcome, ChangeOutcome.updated);
        expect(jsonDecode(target.readAsStringSync()), {'model': 'x'});
      });

      test('creates nothing for a new file', () {
        final target = file('.agents/skills/a/SKILL.md');

        final applied = Reconciler(
          logger: logger,
          dryRun: true,
        ).apply(change(target, 'body', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.created);
        expect(target.existsSync(), isFalse);
      });
    });

    group('writes', () {
      test('leaves no temporary file behind', () {
        final target = file('.claude/settings.json');

        Reconciler(logger: logger)
            .apply(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

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

        final reconciler = Reconciler(logger: logger);
        changes.forEach(reconciler.apply);
        final second = changes.map(reconciler.apply).toList();

        expect(
          second.map((a) => a.outcome),
          everyElement(ChangeOutcome.unchanged),
        );
      });
    });
  });
}
