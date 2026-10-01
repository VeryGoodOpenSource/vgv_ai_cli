import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

import '../document/_markdown_file.dart';

void main() {
  const auditor = ManifestAuditor();
  const reconciler = Reconciler();

  late FileSystem fs;
  late Directory home;
  late ManifestStore manifest;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
    manifest = ManifestStore(home);
  });

  File file(String relative) => fs.file(p.join(home.path, relative));

  File seed(String relative, String contents) => file(relative)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// Installs [changes] with the real reconciler, recording the manifest.
  void install(List<PlannedChange> changes) => manifest.save(
    reconciler.apply(changes, manifest: manifest.load()!).manifest,
  );

  PlannedChange owned(File target, String contents, {Harness? harness}) =>
      PlannedChange.text(file: target, contents: contents, harness: harness);

  PlannedChange json(File target, Object contents, {Harness? harness}) =>
      PlannedChange.text(
        file: target,
        contents: jsonEncode(contents),
        harness: harness,
        mode: ChangeMode.mergeJson,
      );

  PlannedChange toml(File target, String contents) => PlannedChange.text(
    file: target,
    contents: contents,
    harness: Harness.codex,
    mode: ChangeMode.mergeToml,
  );

  PlannedChange markdown(File target, String body, {String name = 'a'}) =>
      PlannedChange.markdown(
        file: target,
        contents: body,
        harness: Harness.gemini,
        section: name,
      );

  ManifestEntry entryFor(File target) => manifest.load()![target.path]!;

  EntryHealth verify(File target) => auditor.verify(entryFor(target), fs);

  /// Reverses the manifest and keeps what it left, unless it was a dry run,
  /// as `uninstall` does.
  Reversal reversal({
    Set<Harness?>? owners,
    bool force = false,
    bool dryRun = false,
  }) {
    final result = auditor.reverse(
      manifest.load()!,
      fs,
      owners: owners,
      force: force,
      dryRun: dryRun,
    );
    if (!dryRun) manifest.save(result.manifest);
    return result;
  }

  List<ReversedEntry> reverse({
    Set<Harness?>? owners,
    bool force = false,
    bool dryRun = false,
  }) => reversal(owners: owners, force: force, dryRun: dryRun).entries;

  ReverseOutcome reverseOne({bool force = false}) =>
      reverse(force: force).single.outcome;

  Map<String, dynamic> readJson(File target) =>
      jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;

  group('ManifestAuditor', () {
    group('verify', () {
      test('reports a file that is gone as missing', () {
        final target = file('.agents/skills/a/SKILL.md');
        install([owned(target, 'body')]);
        target.deleteSync();

        expect(verify(target).status, EntryStatus.missing);
      });

      test('checks an owned file against its hash', () {
        final target = file('.agents/skills/a/SKILL.md');
        install([owned(target, 'body')]);

        expect(verify(target).status, EntryStatus.intact);

        target.writeAsStringSync('edited');
        expect(verify(target).status, EntryStatus.drifted);
      });

      test('finds each JSON key VGV wrote that is gone or changed', () {
        final target = seed('.gemini/settings.json', jsonEncode({'mine': 1}));
        install([
          json(target, {
            'theme': 'vgv',
            'mcpServers': {
              'dart': {'command': 'dart'},
              'gh': {'command': 'gh'},
            },
            'allow': ['Bash', 'Read'],
          }),
        ]);

        expect(verify(target).status, EntryStatus.intact);

        target.writeAsStringSync(
          DocumentFormat.json.encode({
            'mine': 1,
            'theme': 'mine',
            'mcpServers': {
              'dart': {'command': 'dart'},
            },
            'allow': ['Bash'],
          }),
        );
        final health = verify(target);

        expect(health.status, EntryStatus.drifted);
        expect(health.drifted, ['theme']);
        expect(health.missing, ['mcpServers.gh', 'allow']);
      });

      test('reports a key that is only gone as missing', () {
        final target = file('.gemini/settings.json');
        install([
          json(target, {'theme': 'vgv'}),
        ]);
        target.writeAsStringSync('{}');

        expect(verify(target).status, EntryStatus.missing);
      });

      test('does not mind entries the user added to a list VGV wrote', () {
        final target = file('.claude/settings.json');
        install([
          json(target, {
            'allow': ['Bash'],
          }),
        ]);
        target.writeAsStringSync(
          DocumentFormat.json.encode({
            'allow': ['Bash', 'Read'],
          }),
        );

        expect(verify(target).status, EntryStatus.intact);
      });

      test('verifies a TOML document', () {
        final target = seed('.codex/config.toml', '# mine\nmodel = "gpt"\n');
        install([toml(target, '[mcp_servers.dart]\ncommand = "dart"')]);

        expect(verify(target).status, EntryStatus.intact);
      });

      test('reports a document it cannot parse as unparseable', () {
        final target = file('.gemini/settings.json');
        install([
          json(target, {'a': 1}),
        ]);

        target.writeAsStringSync('{ "a": 1, // mine\n}');
        expect(verify(target).status, EntryStatus.unparseable);

        target.writeAsBytesSync([0xff, 0xfe]);
        expect(verify(target).status, EntryStatus.unparseable);
      });

      test('checks each markdown section VGV wrote', () {
        final target = file('.gemini/AGENTS.md');
        install([
          markdown(target, '# A\n'),
          markdown(target, '# B\n', name: 'b'),
        ]);

        expect(verify(target).status, EntryStatus.intact);

        target.writeAsStringSync(
          MarkdownText(target.readAsStringSync())
              .removeSection('a')
              .upsertSection('b', 'x')
              .source,
        );
        final health = verify(target);

        expect(health.status, EntryStatus.drifted);
        expect(health.missing, ['a']);
        expect(health.drifted, ['b']);
      });

      test('reports a markdown file that is not UTF-8 as unparseable', () {
        final target = file('.gemini/AGENTS.md');
        install([markdown(target, '# A\n')]);
        target.writeAsBytesSync([0xff, 0xfe]);

        expect(verify(target).status, EntryStatus.unparseable);
      });

      test('reports a file it cannot read as unreadable', () {
        const entry = OwnedFile(path: '/locked', owner: null, sha256: 'x');
        final fileSystem = _MockFileSystem();
        final locked = _MockFile();
        when(() => fileSystem.file(entry.path)).thenReturn(locked);
        when(locked.existsSync).thenReturn(true);
        when(
          locked.readAsBytesSync,
        ).thenThrow(const FileSystemException('Cannot open file', '/locked'));

        final health = auditor.verify(entry, fileSystem);

        expect(health.status, EntryStatus.unreadable);
        expect(health.error, 'Cannot open file');
      });
    });

    group('reverse', () {
      group('own', () {
        test('deletes the file VGV wrote', () {
          final target = file('.agents/skills/a/SKILL.md');
          install([owned(target, 'body')]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.existsSync(), isFalse);
        });

        test('keeps a file the user has edited, unless forced', () {
          final target = file('.agents/skills/a/SKILL.md');
          install([owned(target, 'body')]);
          target.writeAsStringSync('edited');

          expect(reverseOne(), ReverseOutcome.skipped);
          expect(target.readAsStringSync(), 'edited');

          expect(reverseOne(force: true), ReverseOutcome.removed);
          expect(target.existsSync(), isFalse);
        });

        test('deletes an untouched file through its symlink', () {
          final real = seed('dotfiles/SKILL.md', 'body');
          final target = file('.agents/skills/a/SKILL.md');
          fs.link(target.path).createSync(real.path, recursive: true);
          install([owned(target, 'body')]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(fs.isLinkSync(target.path), isFalse);
          expect(real.existsSync(), isFalse);
        });

        test('deletes only the link the user put in its place, forced', () {
          final target = file('.agents/skills/a/SKILL.md');
          install([owned(target, 'body')]);
          final theirs = seed('dotfiles/SKILL.md', 'theirs');
          target.deleteSync();
          fs.link(target.path).createSync(theirs.path);

          expect(reverseOne(force: true), ReverseOutcome.removed);
          expect(fs.isLinkSync(target.path), isFalse);
          expect(theirs.readAsStringSync(), 'theirs');
        });

        test('reports a file that is already gone as missing', () {
          final target = file('.agents/skills/a/SKILL.md');
          install([owned(target, 'body')]);
          target.deleteSync();

          expect(reverseOne(), ReverseOutcome.missing);
        });
      });

      group('mergeJson', () {
        test("removes VGV's keys and keeps the user's", () {
          final target = seed(
            '.gemini/settings.json',
            DocumentFormat.json.encode({
              'model': 'pro',
              'mcpServers': {
                'mine': {'command': 'mine'},
              },
              'allow': ['Read'],
            }),
          );
          install([
            json(target, {
              'theme': 'vgv',
              'mcpServers': {
                'dart': {'command': 'dart'},
              },
              'allow': ['Bash'],
            }),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(readJson(target), {
            'model': 'pro',
            'mcpServers': {
              'mine': {'command': 'mine'},
            },
            'allow': ['Read'],
          });
        });

        test('keeps a VGV value the user changed, unless forced', () {
          final target = seed(
            '.gemini/settings.json',
            DocumentFormat.json.encode({'a': 1}),
          );
          install([
            json(target, {
              'theme': 'vgv',
              'mcpServers': {
                'dart': {'command': 'dart', 'args': <String>[]},
              },
            }),
          ]);
          target.writeAsStringSync(
            DocumentFormat.json.encode({
              'a': 1,
              'theme': 'mine',
              'mcpServers': {
                'dart': {'command': 'dart', 'args': <String>[]},
              },
            }),
          );

          expect(reverse().single.outcome, ReverseOutcome.partial);
          expect(readJson(target), {'a': 1, 'theme': 'mine'});
          expect(
            manifest.load()!.entries,
            isEmpty,
            reason: 'what the user changed is theirs from then on',
          );
        });

        test('takes back a changed value when forced', () {
          final target = seed(
            '.gemini/settings.json',
            DocumentFormat.json.encode({'a': 1}),
          );
          install([
            json(target, {'theme': 'vgv'}),
          ]);
          target.writeAsStringSync(
            DocumentFormat.json.encode({'a': 1, 'theme': 'mine'}),
          );

          expect(reverseOne(force: true), ReverseOutcome.removed);
          expect(readJson(target), {'a': 1});
        });

        test('reports a document with only changed values as skipped', () {
          final target = seed(
            '.gemini/settings.json',
            DocumentFormat.json.encode({'a': 1}),
          );
          install([
            json(target, {'theme': 'vgv'}),
          ]);
          target.writeAsStringSync(
            DocumentFormat.json.encode({'a': 1, 'theme': 'mine'}),
          );

          expect(reverseOne(), ReverseOutcome.skipped);
          expect(entryFor(target), isA<MergedDocument>());
        });

        test('deletes a document VGV wrote alone', () {
          final target = file('.gemini/settings.json');
          install([
            json(target, {'theme': 'vgv'}),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.existsSync(), isFalse);
        });

        test('reports a document VGV has nothing left in as removed', () {
          final target = seed(
            '.gemini/settings.json',
            DocumentFormat.json.encode({'a': 1}),
          );
          install([
            json(target, {'theme': 'vgv'}),
          ]);
          target.writeAsStringSync(DocumentFormat.json.encode({'a': 1}));

          expect(reverseOne(), ReverseOutcome.removed);
          expect(readJson(target), {'a': 1});
        });

        test('leaves a document it cannot parse alone', () {
          final target = file('.gemini/settings.json');
          install([
            json(target, {'a': 1}),
          ]);
          target.writeAsStringSync('{ "a": 1, // mine\n}');

          expect(reverseOne(), ReverseOutcome.unparseable);
          expect(target.readAsStringSync(), '{ "a": 1, // mine\n}');
          expect(entryFor(target), isA<MergedDocument>());
        });
      });

      group('mergeToml', () {
        test("removes VGV's keys and tables, keeping comments", () {
          const original =
              '# My Codex setup\n'
              'model = "gpt-5" # explicit\n'
              '\n'
              '[mcp_servers.dart]\n'
              'command = "dart" # mine\n';
          final target = seed('.codex/config.toml', original);
          install([
            toml(
              target,
              '[mcp_servers.dart]\ncommand = "dart"\nargs = ["mcp"]\n'
              '[mcp_servers.docs]\nurl = "https://docs"',
            ),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.readAsStringSync(), original);
        });

        test('keeps the file when an edit cannot be made in place', () {
          final target = seed('.codex/config.toml', 'model = "gpt"\n');
          install([toml(target, '[mcp_servers.dart]\ncommand = "dart"')]);
          const dotted =
              '# mine\nmodel = "gpt"\nmcp_servers.dart.command = "dart"\n';
          target.writeAsStringSync(dotted);

          expect(reverseOne(), ReverseOutcome.skipped);
          expect(target.readAsStringSync(), dotted);
        });

        test('re-serializes when forced and no edit fits', () {
          final target = seed('.codex/config.toml', 'model = "gpt"\n');
          install([toml(target, '[mcp_servers.dart]\ncommand = "dart"')]);
          target.writeAsStringSync(
            '# mine\nmodel = "gpt"\nmcp_servers.dart.command = "dart"\n',
          );

          expect(reverseOne(force: true), ReverseOutcome.removed);
          expect(TomlDocument.parse(target.readAsStringSync()).toMap(), {
            'model': 'gpt',
          });
        });

        test('deletes a document VGV wrote alone', () {
          final target = file('.codex/config.toml');
          install([toml(target, '[mcp_servers.dart]\ncommand = "dart"')]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.existsSync(), isFalse);
        });

        test("keeps a document with only the user's comments left", () {
          final target = seed('.codex/config.toml', '# notes\n');
          install([toml(target, 'model = "gpt"')]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.readAsStringSync(), '# notes\n');
        });
      });

      group('mergeMarkdown', () {
        test("removes VGV's sections and keeps the user's text", () {
          const original = '# Mine\n\nBe terse.\n';
          final target = seed('.gemini/AGENTS.md', original);
          install([
            markdown(target, '# A\n'),
            markdown(target, '# B\n', name: 'b'),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.readAsStringSync(), original);
        });

        test('keeps a section the user edited, unless forced', () {
          final target = seed('.gemini/AGENTS.md', 'Mine.\n');
          install([
            markdown(target, '# A\n'),
            markdown(target, '# B\n', name: 'b'),
          ]);
          target.editSection('b', 'edited');

          expect(reverseOne(), ReverseOutcome.partial);
          expect(target.sectionBody('a'), isNull);
          expect(target.sectionBody('b'), 'edited');
          expect((entryFor(target) as MarkdownSections).sections.keys, ['b']);
        });

        test('keeps recording an edited section it kept, for install', () {
          final target = seed('.gemini/AGENTS.md', 'Mine.\n');
          install([
            markdown(target, '# A\n'),
            markdown(target, '# B\n', name: 'b'),
          ]);
          target.editSection('b', 'edited');
          reverse();

          install([markdown(target, '# B\n', name: 'b')]);

          expect(target.sectionBody('b'), 'edited');
        });

        test('skips a file whose only section the user edited', () {
          final target = seed('.gemini/AGENTS.md', 'Mine.\n');
          install([markdown(target, '# A\n')]);
          target.editSection('a', 'edited');

          expect(reverseOne(), ReverseOutcome.skipped);
          expect(reverseOne(force: true), ReverseOutcome.removed);
          expect(target.readAsStringSync(), 'Mine.\n');
        });

        test('deletes a file VGV wrote alone', () {
          final target = file('.gemini/AGENTS.md');
          install([markdown(target, '# A\n')]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.existsSync(), isFalse);
        });

        test('reports a file whose sections are gone as removed', () {
          final target = seed('.gemini/AGENTS.md', 'Mine.\n');
          install([markdown(target, '# A\n')]);
          target.writeAsStringSync('Mine.\n');

          expect(reverseOne(), ReverseOutcome.removed);
          expect(target.readAsStringSync(), 'Mine.\n');
        });

        test('leaves a file that is not UTF-8 alone', () {
          final target = file('.gemini/AGENTS.md');
          install([markdown(target, '# A\n')]);
          target.writeAsBytesSync([0xff, 0xfe]);

          expect(reverseOne(), ReverseOutcome.unparseable);
        });
      });

      group('the manifest', () {
        test('keeps only the entries that still hold something of VGV', () {
          final kept = file('.agents/skills/a/SKILL.md');
          final gone = file('.agents/skills/b/SKILL.md');
          install([owned(kept, 'a'), owned(gone, 'b')]);
          kept.writeAsStringSync('edited');

          reverse();

          expect(manifest.load()!.entries.map((e) => e.path), [kept.path]);
        });

        test('is deleted once nothing is left in it', () {
          install([owned(file('.agents/skills/a/SKILL.md'), 'a')]);

          reverse();

          expect(manifest.file.existsSync(), isFalse);
        });

        test('reverses only the owners asked for', () {
          final shared = file('.agents/skills/a/SKILL.md');
          final gemini = file('.gemini/agents/a.md');
          install([
            owned(shared, 'a'),
            owned(gemini, 'a', harness: Harness.gemini),
          ]);

          final reversed = reverse(owners: {Harness.gemini});

          expect(reversed.map((r) => r.entry.path), [gemini.path]);
          expect(shared.existsSync(), isTrue);
          expect(gemini.existsSync(), isFalse);
          expect(manifest.load()!.entries.map((e) => e.path), [shared.path]);
        });

        test('touches nothing on a dry run, but returns what it would', () {
          final target = file('.agents/skills/a/SKILL.md');
          install([owned(target, 'a')]);
          final before = manifest.file.readAsStringSync();

          final result = reversal(dryRun: true);

          expect(result.entries.single.outcome, ReverseOutcome.removed);
          expect(result.manifest.entries, isEmpty);
          expect(target.existsSync(), isTrue);
          expect(manifest.file.readAsStringSync(), before);
        });

        test('does nothing with an empty manifest', () {
          final result = auditor.reverse(InstallManifest(), fs);

          expect(result.entries, isEmpty);
          expect(result.manifest.entries, isEmpty);
        });
      });

      test('reports a file it cannot write as failed and goes on', () {
        final blocked = seed(
          '.gemini/settings.json',
          DocumentFormat.json.encode({'a': 1}),
        );
        final fine = file('.agents/skills/a/SKILL.md');
        install([
          json(blocked, {'theme': 'vgv'}),
          owned(fine, 'a'),
        ]);
        fs.directory('${blocked.path}.vgv-tmp').createSync();

        final reversed = reverse();

        expect(reversed.map((r) => r.outcome), [
          ReverseOutcome.failed,
          ReverseOutcome.removed,
        ]);
        expect(reversed.first.error, isNotEmpty);
        expect(entryFor(blocked), isA<MergedDocument>());
      });

      group('symlinks', () {
        late File real;
        late File linked;

        setUp(() {
          real = seed(
            'dotfiles/settings.json',
            DocumentFormat.json.encode({'a': 1}),
          );
          fs.link(file('.gemini/settings.json').path)
            ..parent.createSync(recursive: true)
            ..createSync(real.path);
          linked = file('.gemini/settings.json');
        });

        test('takes VGV back out of the file a symlink points to', () {
          install([
            json(linked, {'theme': 'vgv'}),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(fs.isLinkSync(linked.path), isTrue);
          expect(readJson(real), {'a': 1});
        });

        test('deletes the link and its target once nothing is left', () {
          real.writeAsStringSync('');
          install([
            json(linked, {'theme': 'vgv'}),
          ]);

          expect(reverseOne(), ReverseOutcome.removed);
          expect(fs.isLinkSync(linked.path), isFalse);
          expect(real.existsSync(), isFalse);
        });
      });
    });

    group('round trip', () {
      test('install then reverse leaves every user file as it was', () {
        final settings = DocumentFormat.json.encode({
          'model': 'pro',
          'mcpServers': {
            'mine': {'command': 'mine'},
          },
          'allow': ['Read'],
        });
        const config =
            '# My Codex setup\n'
            'model = "gpt-5" # explicit\n'
            '\n'
            '[mcp_servers.mine]\n'
            'command = "mine"\n';
        const agents = '# Mine\n\nBe terse.\n';
        final seeded = {
          seed('.gemini/settings.json', settings): settings,
          seed('.codex/config.toml', config): config,
          seed('.gemini/AGENTS.md', agents): agents,
        };
        final skill = file('.agents/skills/a/SKILL.md');

        install([
          owned(skill, 'body'),
          json(file('.gemini/settings.json'), {
            'mcpServers': {
              'dart': {
                'command': 'dart',
                'args': ['mcp-server'],
              },
            },
            'allow': ['Bash'],
          }, harness: Harness.gemini),
          toml(
            file('.codex/config.toml'),
            '[mcp_servers.dart]\ncommand = "dart"\nargs = ["mcp-server"]',
          ),
          markdown(file('.gemini/AGENTS.md'), '# VGV\n\nUse the skills.\n'),
        ]);
        final reversed = reverse();

        expect(
          reversed.map((r) => r.outcome),
          everyElement(ReverseOutcome.removed),
        );
        for (final MapEntry(key: target, value: original) in seeded.entries) {
          expect(target.readAsStringSync(), original, reason: target.path);
        }
        expect(skill.existsSync(), isFalse);
        expect(manifest.file.existsSync(), isFalse);
      });
    });
  });
}

class _MockFileSystem extends Mock implements FileSystem;

class _MockFile extends Mock implements File;
