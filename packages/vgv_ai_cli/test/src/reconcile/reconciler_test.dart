import 'dart:convert';
import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/applied_change.dart';
import 'package:vgv_ai_cli/src/reconcile/markdown_sections.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

void main() {
  const reconciler = Reconciler();

  late FileSystem fileSystem;
  late Directory home;
  late File manifest;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    home = fileSystem.directory('/home/dev')..createSync(recursive: true);
    manifest = installManifest(home);
  });

  AppliedChange applyOne(
    PlannedChange change, {
    bool force = false,
    bool dryRun = false,
  }) => reconciler
      .apply([change], manifest: manifest, force: force, dryRun: dryRun)
      .single;

  File file(String relative) => fileSystem.file(p.join(home.path, relative));

  File seed(String relative, String contents) {
    final f = file(relative)..parent.createSync(recursive: true);
    return f..writeAsStringSync(contents);
  }

  PlannedChange change(File target, String contents, ChangeMode mode) =>
      PlannedChange.text(
        file: target,
        contents: contents,
        harness: null,
        mode: mode,
      );

  Map<String, dynamic> readJson(File target) =>
      jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;

  group('Reconciler', () {
    group('own', () {
      test('creates a file that did not exist', () {
        final target = file('.agents/skills/testing/SKILL.md');
        final applied = applyOne(change(target, 'body', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.created);
        expect(target.readAsStringSync(), 'body');
      });

      test('overwrites a file it wrote and the user left alone', () {
        final target = file('.agents/skills/a/SKILL.md');
        applyOne(change(target, 'old', ChangeMode.own));

        final applied = applyOne(change(target, 'new', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.updated);
        expect(target.readAsStringSync(), 'new');
      });

      test('keeps a file of the user at a path it owns', () {
        final target = seed('.codex/prompts/plan.md', 'my own plan prompt');

        final applied = applyOne(change(target, 'vgv', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(target.readAsStringSync(), 'my own plan prompt');
      });

      test('keeps a file it wrote once the user has edited it', () {
        final target = file('.agents/skills/a/SKILL.md');
        applyOne(change(target, 'old', ChangeMode.own));
        target.writeAsStringSync('edited');

        final applied = applyOne(change(target, 'new', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(target.readAsStringSync(), 'edited');
      });

      test("takes the user's file when forced, and owns it after", () {
        final target = seed('.codex/prompts/plan.md', 'mine');

        final forced = applyOne(
          change(target, 'vgv', ChangeMode.own),
          force: true,
        );
        final later = applyOne(change(target, 'vgv 2', ChangeMode.own));

        expect(forced.outcome, ChangeOutcome.updated);
        expect(later.outcome, ChangeOutcome.updated);
        expect(target.readAsStringSync(), 'vgv 2');
      });

      test('writes bytes that are not UTF-8 untouched', () {
        final target = file('.agents/skills/a/logo.png');
        final bytes = [0x89, 0x50, 0x4e, 0x47, 0xff, 0xfe];

        applyOne(PlannedChange(file: target, bytes: bytes, harness: null));

        expect(target.readAsBytesSync(), bytes);
      });

      test('reports unchanged when content already matches', () {
        final target = seed('.agents/skills/a/SKILL.md', 'body');
        final applied = applyOne(change(target, 'body', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.unchanged);
      });
    });

    group('mergeJson', () {
      test('writes incoming content into an empty target', () {
        final target = seed('.claude/settings.json', '   ');

        applyOne(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

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

        applyOne(
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

        applyOne(
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

        applyOne(
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

        applyOne(
          change(target, jsonEncode({'model': 'y'}), ChangeMode.mergeJson),
          force: true,
        );

        expect(readJson(target)['model'], 'y');
      });

      test('reports a write that kept a user value as partial', () {
        final target = seed(
          '.gemini/settings.json',
          jsonEncode({'model': 'x'}),
        );

        final applied = applyOne(
          change(
            target,
            jsonEncode({'model': 'y', 'added': true}),
            ChangeMode.mergeJson,
          ),
        );

        expect(applied.outcome, ChangeOutcome.partial);
        expect(readJson(target), {'model': 'x', 'added': true});
      });

      test('leaves an unparseable file alone rather than discarding it', () {
        final target = seed('.claude/settings.json', '{ not json');

        final applied = applyOne(
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        );

        expect(applied.outcome, ChangeOutcome.unparseable);
        expect(target.readAsStringSync(), '{ not json');
      });

      test('leaves the file alone when the existing root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode([1, 2, 3]));

        applyOne(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

        expect(jsonDecode(target.readAsStringSync()), [1, 2, 3]);
      });

      test('leaves the file alone when the incoming root is not a map', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        applyOne(change(target, jsonEncode([1, 2]), ChangeMode.mergeJson));

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

        final planned = change(target, jsonEncode(hooks), ChangeMode.mergeJson);
        applyOne(planned);
        final second = applyOne(planned);

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

        final applied = applyOne(
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

        final applied = applyOne(
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

        applyOne(
          change(target, jsonEncode({'model': 'opus'}), ChangeMode.mergeJson),
          force: true,
        );

        expect(readJson(target)['model'], 'opus');
      });

      test('leaves the file alone when the incoming JSON is unparseable', () {
        final target = seed('.claude/settings.json', jsonEncode({'a': 1}));

        final applied = applyOne(
          change(target, '{ not json', ChangeMode.mergeJson),
        );

        expect(jsonDecode(target.readAsStringSync()), {'a': 1});
        expect(applied.outcome, ChangeOutcome.unparseable);
      });

      test('creates nothing when the incoming JSON is unparseable', () {
        final target = file('.claude/settings.json');

        final applied = applyOne(
          change(target, '{ not json', ChangeMode.mergeJson),
        );

        expect(target.existsSync(), isFalse);
        expect(applied.outcome, ChangeOutcome.unparseable);
      });

      test('recurses into nested maps', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({
            'nested': {'kept': 1},
          }),
        );

        applyOne(
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

        applyOne(
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

        applyOne(
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

        applyOne(change(target, 'loose = "value"', ChangeMode.mergeToml));

        final result = readToml(target);
        expect(result['model'], 'gpt');
        expect(result['loose'], 'value');
      });

      test('keeps a value the user edited', () {
        const edited = '[mcp_servers.dart]\ncommand = "custom"\n';
        final target = seed('.codex/config.toml', edited);

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(target.readAsStringSync(), edited);
      });

      test('overwrites a value the user edited when forced', () {
        final target = seed(
          '.codex/config.toml',
          '[mcp_servers.dart]\ncommand = "custom"\nextra = "mine"\n',
        );

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
          force: true,
        );

        expect((readToml(target)['mcp_servers'] as Map)['dart'], {
          'command': 'dart',
          'extra': 'mine',
        });
        expect(applied.outcome, ChangeOutcome.updated);
      });

      test("keeps the user's comments when it adds a table", () {
        const original =
            '# My Codex setup\n'
            'model = "gpt" # the fast one\n'
            '\n'
            '[mcp_servers.mine]\n'
            'url = "https://example.com"\n';
        final target = seed('.codex/config.toml', original);

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.updated);
        expect(target.readAsStringSync(), startsWith(original));
        expect((readToml(target)['mcp_servers'] as Map).keys, ['mine', 'dart']);
      });

      test('adds a table and reports the value it kept as partial', () {
        final target = seed(
          '.codex/config.toml',
          '# mine\n[mcp_servers.dart]\ncommand = "custom"\n',
        );

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"\n'
            '[mcp_servers.gh]\ncommand = "gh"',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.partial);
        expect(target.readAsStringSync(), startsWith('# mine\n'));
        expect(readToml(target)['mcp_servers'], {
          'dart': {'command': 'custom'},
          'gh': {'command': 'gh'},
        });
      });

      test('grows an inline array in place, keeping comments', () {
        final target = seed(
          '.codex/config.toml',
          '# mine\n[mcp_servers.dart]\nargs = ["a"] # first\n'
              '\n[other]\nx = 1\n',
        );

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\nargs = ["b"]',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.updated);
        expect(
          target.readAsStringSync(),
          "# mine\n[mcp_servers.dart]\nargs = ['a', 'b'] # first\n"
          '\n[other]\nx = 1\n',
        );
      });

      test('adds a key to a table the user already has', () {
        const original =
            '# My Codex setup\n'
            'model = "gpt"\n'
            '\n'
            '[mcp_servers.dart]\n'
            'command = "dart" # pinned\n'
            '\n'
            '[profiles.fast]\n'
            'model = "mini"\n';
        final target = seed('.codex/config.toml', original);

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"\nargs = ["mcp-server"]',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.updated);
        expect(
          target.readAsStringSync(),
          original.replaceFirst(
            '# pinned\n',
            "# pinned\nargs = ['mcp-server']\n",
          ),
        );
      });

      test("replaces a forced value in place, keeping the user's comments", () {
        final target = seed(
          '.codex/config.toml',
          '# mine\n[mcp_servers.dart]\ncommand = "custom"\n',
        );

        applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
          force: true,
        );

        expect(
          target.readAsStringSync(),
          "# mine\n[mcp_servers.dart]\ncommand = 'dart'\n",
        );
      });

      test('skips an edit it cannot make without rewriting the file', () {
        const original = '# mine\nmcp_servers.dart.args = ["a"]\n';
        final target = seed('.codex/config.toml', original);

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\nargs = ["b"]',
            ChangeMode.mergeToml,
          ),
        );

        expect(
          applied.outcome,
          ChangeOutcome.skipped,
          reason:
              'a dotted key cannot be edited in place, and re-serializing '
              "the file would drop the user's comments",
        );
        expect(target.readAsStringSync(), original);
      });

      test('rewrites the file when forced and no edit fits', () {
        final target = seed(
          '.codex/config.toml',
          '# mine\nmcp_servers.dart.args = ["a"]\n',
        );

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\nargs = ["b"]',
            ChangeMode.mergeToml,
          ),
          force: true,
        );

        expect(applied.outcome, ChangeOutcome.updated);
        expect((readToml(target)['mcp_servers'] as Map)['dart'], {
          'args': ['a', 'b'],
        });
      });

      test('unions arrays of tables', () {
        final target = seed('.codex/config.toml', '[[server]]\nname = "a"\n');

        applyOne(
          change(target, '[[server]]\nname = "b"', ChangeMode.mergeToml),
        );

        expect(readToml(target)['server'], [
          {'name': 'a'},
          {'name': 'b'},
        ]);
      });

      test('reports unchanged when the merge adds nothing', () {
        final target = seed('.codex/config.toml', 'model = "gpt"\n');

        final applied = applyOne(
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

        final applied = applyOne(
          change(target, '[unterminated', ChangeMode.mergeToml),
        );

        expect(applied.outcome, ChangeOutcome.unparseable);
        expect(target.readAsStringSync(), 'model = "gpt"\n');
      });

      test('leaves the file alone when it cannot be parsed', () {
        final target = seed('.codex/config.toml', '[unterminated');

        final applied = applyOne(
          change(
            target,
            '[mcp_servers.dart]\ncommand = "dart"',
            ChangeMode.mergeToml,
          ),
        );

        expect(applied.outcome, ChangeOutcome.unparseable);
        expect(target.readAsStringSync(), '[unterminated');
      });
    });

    group('mergeMarkdown', () {
      final start = sectionStart('instructions');
      final end = sectionEnd('instructions');

      AppliedChange apply(
        File target,
        String contents, {
        String section = 'instructions',
      }) => applyOne(
        PlannedChange.markdown(
          file: target,
          contents: contents,
          harness: null,
          section: section,
        ),
      );

      test('writes the delimited section into a new file', () {
        final target = file('.gemini/AGENTS.md');

        final applied = apply(target, '# VGV\n');

        expect(applied.outcome, ChangeOutcome.created);
        expect(target.readAsStringSync(), '$start\n# VGV\n$end\n');
      });

      test("appends the section after the user's own instructions", () {
        final target = seed('.gemini/AGENTS.md', '# Mine\n\nBe terse.\n');

        final applied = apply(target, '# VGV\n');

        expect(applied.outcome, ChangeOutcome.updated);
        expect(
          target.readAsStringSync(),
          '# Mine\n\nBe terse.\n\n$start\n# VGV\n$end\n',
        );
      });

      test('replaces only its own section on a later install', () {
        final target = seed(
          '.gemini/AGENTS.md',
          '# Mine\n\n$start\n# Old\n$end\n\n# Also mine\n',
        );

        apply(target, '# New\n');

        expect(
          target.readAsStringSync(),
          '# Mine\n\n$start\n# New\n$end\n\n# Also mine\n',
        );
      });

      test('rewrites one named section and leaves its siblings alone', () {
        final target = file('.gemini/AGENTS.md');
        apply(target, '# Instructions\n');
        apply(target, '# Persona\n', section: 'persona');

        apply(target, '# Instructions v2\n');

        expect(
          target.readAsStringSync(),
          '$start\n# Instructions v2\n$end\n\n'
          '${sectionStart('persona')}\n# Persona\n${sectionEnd('persona')}\n',
        );
      });

      test('reports unchanged when the section already matches', () {
        final target = file('.gemini/AGENTS.md');
        apply(target, '# VGV\n');

        expect(apply(target, '# VGV\n').outcome, ChangeOutcome.unchanged);
      });

      test('keeps the text after an orphaned start marker on every run', () {
        final target = seed('.gemini/AGENTS.md', '$start\nhalf\n\nMine.\n');

        apply(target, '# VGV\n');
        final second = apply(target, '# VGV\n');

        expect(second.outcome, ChangeOutcome.unchanged);
        expect(
          target.readAsStringSync(),
          '$start\nhalf\n\nMine.\n\n$start\n# VGV\n$end\n',
        );
      });

      test('appends a fresh section when only the start marker survives', () {
        final target = seed('.gemini/AGENTS.md', '$start\nhalf\n');

        apply(target, '# VGV\n');

        expect(
          target.readAsStringSync(),
          '$start\nhalf\n\n$start\n# VGV\n$end\n',
        );
      });
    });

    group('dryRun', () {
      test('reports the change without touching disk', () {
        final target = seed(
          '.claude/settings.json',
          jsonEncode({'model': 'x'}),
        );

        final applied = applyOne(
          change(target, jsonEncode({'other': 1}), ChangeMode.mergeJson),
          dryRun: true,
        );

        expect(applied.outcome, ChangeOutcome.updated);
        expect(jsonDecode(target.readAsStringSync()), {'model': 'x'});
      });

      test('creates nothing for a new file', () {
        final target = file('.agents/skills/a/SKILL.md');

        final applied = applyOne(
          change(target, 'body', ChangeMode.own),
          dryRun: true,
        );

        expect(applied.outcome, ChangeOutcome.created);
        expect(target.existsSync(), isFalse);
      });
    });

    group('writes', () {
      test('leaves no temporary file behind', () {
        final target = file('.claude/settings.json');

        applyOne(change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson));

        expect(target.parent.listSync().map((e) => e.path), [
          target.path,
        ], reason: 'the write goes through a sibling temp file and renames it');
      });
    });

    group('non-UTF-8 files', () {
      test('leaves a config it cannot decode alone', () {
        final target = file('.gemini/settings.json')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe]);

        final applied = applyOne(
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        );

        expect(applied.outcome, ChangeOutcome.unparseable);
        expect(target.readAsBytesSync(), [0xff, 0xfe]);
      });
    });

    group('manifest', () {
      Map<String, dynamic> readManifest() => readJson(manifest);

      test('lives under ~/.vgv_ai', () {
        expect(manifest.path, p.join(home.path, '.vgv_ai', 'manifest.json'));
      });

      test('records every owned file it writes, and no merged one', () {
        final skill = file('.agents/skills/a/SKILL.md');
        final settings = file('.claude/settings.json');

        reconciler.apply([
          change(skill, 'body', ChangeMode.own),
          change(settings, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ], manifest: manifest);

        expect(readManifest().keys, [skill.path]);
      });

      test('keeps entries for files this run did not touch', () {
        manifest
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'/elsewhere': 'hash'}));
        final skill = file('.agents/skills/a/SKILL.md');

        applyOne(change(skill, 'body', ChangeMode.own));

        expect(
          readManifest().keys,
          unorderedEquals(['/elsewhere', skill.path]),
        );
      });

      test('is not rewritten when nothing it records changed', () {
        final skill = change(
          file('.agents/skills/a/SKILL.md'),
          'body',
          ChangeMode.own,
        );
        applyOne(skill);
        final compact = jsonEncode(readManifest());
        manifest.writeAsStringSync(compact);

        applyOne(skill);

        expect(manifest.readAsStringSync(), compact);
      });

      test('is not written on a dry run', () {
        applyOne(
          change(file('.agents/skills/a/SKILL.md'), 'body', ChangeMode.own),
          dryRun: true,
        );

        expect(manifest.existsSync(), isFalse);
      });

      test('treats a malformed manifest, or an odd entry, as unrecorded', () {
        final target = seed('.agents/skills/a/SKILL.md', 'old');
        manifest
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({target.path: 1}));

        final applied = applyOne(change(target, 'new', ChangeMode.own));
        manifest.writeAsStringSync('{ not json');
        final again = applyOne(change(target, 'newer', ChangeMode.own));

        expect(applied.outcome, ChangeOutcome.skipped);
        expect(again.outcome, ChangeOutcome.skipped);
      });

      test('reports a manifest it cannot write as a failed change', () {
        fileSystem.directory(manifest.path).createSync(recursive: true);
        final skill = file('.agents/skills/a/SKILL.md');

        final applied = reconciler.apply([
          change(skill, 'body', ChangeMode.own),
        ], manifest: manifest);

        expect(applied.map((a) => a.outcome), [
          ChangeOutcome.created,
          ChangeOutcome.failed,
        ]);
        expect(applied.last.change.file.path, manifest.path);
      });
    });

    group('failures', () {
      test('reports a path it cannot write and applies the rest', () {
        final blocked = file('.codex/agents/a.toml');
        fileSystem.directory(blocked.path).createSync(recursive: true);
        final fine = file('.codex/agents/b.toml');

        final applied = reconciler.apply([
          change(blocked, 'a', ChangeMode.own),
          change(fine, 'b', ChangeMode.own),
        ], manifest: manifest);

        expect(applied.first.outcome, ChangeOutcome.failed);
        expect(applied.first.error, isNotEmpty);
        expect(applied[1].outcome, ChangeOutcome.created);
        expect(fine.readAsStringSync(), 'b');
      });

      test('leaves no temporary file behind when a write fails', () {
        final blocked = file('.codex/agents/a.toml');
        fileSystem.directory(blocked.path).createSync(recursive: true);

        applyOne(change(blocked, 'a', ChangeMode.own));

        expect(
          fileSystem.file('${blocked.path}.vgv-tmp').existsSync(),
          isFalse,
        );
      });
    });

    group('symlinks', () {
      test('writes through a symlinked config rather than replacing it', () {
        final real = seed('dotfiles/settings.json', jsonEncode({'a': 1}));
        final link = file('.claude/settings.json');
        link.parent.createSync(recursive: true);
        fileSystem.link(link.path).createSync(real.path);

        applyOne(change(link, jsonEncode({'b': 2}), ChangeMode.mergeJson));

        expect(fileSystem.isLinkSync(link.path), isTrue);
        expect(readJson(real), {'a': 1, 'b': 2});
      });
    });

    group('permissions', () {
      // The in-memory file system has no file modes, so these run on disk.
      late Directory temp;

      setUp(() {
        temp = const LocalFileSystem().systemTempDirectory.createTempSync();
        addTearDown(() => temp.deleteSync(recursive: true));
      });

      File onDisk(String name, {String? contents, String? mode}) {
        final created = temp.childFile(name);
        if (contents != null) created.writeAsStringSync(contents);
        if (mode != null) Process.runSync('chmod', [mode, created.path]);
        return created;
      }

      int modeOf(File target) => target.statSync().mode & 0x1ff;

      test('a new file takes the mode of the file it was copied from', () {
        final script = onDisk('source.sh', contents: 'echo', mode: '755');
        final target = onDisk('copied.sh');

        reconciler.apply([
          PlannedChange(
            file: target,
            bytes: utf8.encode('echo'),
            harness: null,
            source: script,
          ),
        ], manifest: temp.childFile('manifest.json'));

        expect(modeOf(target), modeOf(script));
      });

      test('an updated file keeps its own mode', () {
        final target = onDisk('settings.json', contents: '{}', mode: '600');

        reconciler.apply([
          change(target, jsonEncode({'a': 1}), ChangeMode.mergeJson),
        ], manifest: temp.childFile('manifest.json'));

        expect(modeOf(target), int.parse('600', radix: 8));
        expect(readJson(target), {'a': 1});
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

        reconciler.apply(changes, manifest: manifest);
        final second = reconciler.apply(changes, manifest: manifest);

        expect(
          second.map((a) => a.outcome),
          everyElement(ChangeOutcome.unchanged),
        );
      });
    });
  });
}
