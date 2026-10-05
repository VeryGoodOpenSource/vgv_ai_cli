import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/version.dart';

class _MockLogger extends Mock implements Logger;

class _MockPubUpdater extends Mock implements PubUpdater;

/// A [ManifestAuditor] that fails to reverse every entry it is given.
class _FailingAuditor extends ManifestAuditor {
  const new();

  @override
  Reversal reverse(
    InstallManifest manifest,
    FileSystem fileSystem, {
    Set<Harness?>? owners,
    bool force = false,
    bool dryRun = false,
  }) => Reversal(
    entries: [
      for (final entry in manifest.entries)
        ReversedEntry.failed(entry, error: 'Permission denied'),
    ],
    manifest: manifest,
  );
}

void main() {
  group('uninstall', () {
    late Logger logger;
    late PubUpdater pubUpdater;
    late FileSystem fs;
    late Directory home;
    late ManifestStore store;

    /// A directory that cannot be deleted, or null when every one can.
    String? undeletable;

    setUp(() {
      logger = _MockLogger();
      pubUpdater = _MockPubUpdater();
      undeletable = null;
      fs = MemoryFileSystem.test(
        opHandle: (path, operation) {
          if (path == undeletable && operation == FileSystemOp.delete) {
            throw FileSystemException('Cannot delete', path);
          }
        },
      );
      home = fs.directory('/home/dev')..createSync(recursive: true);
      store = ManifestStore(home);

      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
    });

    Future<int> runThroughRunner(UninstallCommand command, List<String> args) =>
        VgvAiCliCommandRunner(
          logger: logger,
          pubUpdater: pubUpdater,
          uninstallCommand: command,
        ).run(['uninstall', ...args]);

    Future<int> runUninstall([
      List<String> args = const [],
      ManifestAuditor auditor = const ManifestAuditor(),
    ]) => runThroughRunner(
      UninstallCommand(logger: logger, home: home, auditor: auditor),
      args,
    );

    File homeFile(String relativePath) =>
        fs.file(fs.path.join(home.path, relativePath));

    File seed(String relativePath, String contents) => homeFile(relativePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

    /// Installs [changes] with the real reconciler, recording the manifest.
    void install(List<PlannedChange> changes) => store.save(
      const Reconciler().apply(changes, manifest: store.load()!).manifest,
    );

    PlannedChange owned(Harness? harness, String relativePath) =>
        PlannedChange.text(
          file: homeFile(relativePath),
          contents: 'vgv',
          harness: harness,
        );

    PlannedChange json(Harness harness, String relativePath, Object value) =>
        PlannedChange.text(
          file: homeFile(relativePath),
          contents: jsonEncode(value),
          harness: harness,
          mode: ChangeMode.mergeJson,
        );

    Map<String, dynamic> readJson(File file) =>
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    test('describes itself', () {
      final command = UninstallCommand(logger: logger);

      expect(command.name, UninstallCommand.commandName);
      expect(command.description, contains('Remove'));
    });

    group('with no flags', () {
      test('removes everything the manifest records', () async {
        final settings = seed('.claude/settings.json', '{"theme":"dark"}');
        install([
          owned(null, '.agents/skills/a/SKILL.md'),
          owned(Harness.gemini, '.gemini/commands/vgv/a.toml'),
          json(Harness.claude, '.claude/settings.json', {'vgv': true}),
        ]);

        final exitCode = await runUninstall();

        expect(exitCode, ExitCode.success.code);
        expect(homeFile('.agents/skills/a/SKILL.md').existsSync(), isFalse);
        expect(homeFile('.gemini/commands/vgv/a.toml').existsSync(), isFalse);
        expect(readJson(settings), {'theme': 'dark'});
        expect(store.file.existsSync(), isFalse);
        verify(() => logger.detail('Removed ${settings.path}')).called(1);
        verify(
          () => logger.info(
            '\nRestart your coding agents to pick up the changes.',
          ),
        ).called(1);
      });

      test(
        'says there is nothing to remove when nothing is recorded',
        () async {
          final exitCode = await runUninstall();

          expect(exitCode, ExitCode.success.code);
          expect(store.file.existsSync(), isFalse);
          verify(
            () => logger.info(
              "VGV AI CLI hasn't installed anything here, so there is nothing "
              'to remove.',
            ),
          ).called(1);
        },
      );

      test('exits with an I/O error when an entry fails', () async {
        install([owned(Harness.codex, '.codex/AGENTS.md')]);
        final recorded = store.file.readAsStringSync();

        final exitCode = await runUninstall(const [], const _FailingAuditor());

        expect(exitCode, ExitCode.ioError.code);
        expect(store.file.readAsStringSync(), recorded);
        verify(
          () => logger.err(
            'Could not update ${homeFile('.codex/AGENTS.md').path}: '
            'Permission denied',
          ),
        ).called(1);
      });
    });

    group('selection', () {
      const sharedSkill = '.agents/skills/a/SKILL.md';
      const codexFile = '.codex/AGENTS.md';
      const piFile = '.pi/agent/AGENTS.md';

      final sharedStillPresent =
          'The shared skills VGV AI CLI installed are still in '
          '/home/dev/.agents/skills. Run ${lightCyan.wrap('vgv_ai uninstall')} '
          'with no flags to remove them.';

      setUp(
        () => install([
          owned(null, sharedSkill),
          owned(Harness.codex, codexFile),
          owned(Harness.pi, piFile),
        ]),
      );

      Set<Harness?> recordedOwners() => {
        for (final entry in store.load()!.entries) entry.owner,
      };

      test('--only removes just the named harnesses', () async {
        final exitCode = await runUninstall(['--only', 'codex']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(codexFile).existsSync(), isFalse);
        expect(homeFile(piFile).existsSync(), isTrue);
        expect(homeFile(sharedSkill).existsSync(), isTrue);
        expect(recordedOwners(), {null, Harness.pi});
        verify(() => logger.info(sharedStillPresent)).called(1);
      });

      test('--no-<harness> removes every other harness', () async {
        final exitCode = await runUninstall(['--no-codex']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(codexFile).existsSync(), isTrue);
        expect(homeFile(piFile).existsSync(), isFalse);
        expect(homeFile(sharedSkill).existsSync(), isTrue);
        expect(recordedOwners(), {null, Harness.codex});
        verify(() => logger.info(sharedStillPresent)).called(1);
      });

      test('removes the shared skills with every recorded harness', () async {
        final exitCode = await runUninstall([
          '--only',
          'codex',
          '--only',
          'pi',
        ]);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(sharedSkill).existsSync(), isFalse);
        expect(store.file.existsSync(), isFalse);
        verifyNever(() => logger.info(sharedStillPresent));
      });

      test('--only cannot be combined with a harness flag', () async {
        final exitCode = await runUninstall(['--only', 'codex', '--no-pi']);

        expect(exitCode, ExitCode.usage.code);
        expect(homeFile(codexFile).existsSync(), isTrue);
        verify(() => logger.err('--only cannot be combined with --[no-]pi.'))
            .called(1);
      });

      test('says when --only names a harness with nothing recorded', () async {
        final recorded = store.file.readAsStringSync();

        final exitCode = await runUninstall(['--only', 'gemini']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(sharedSkill).existsSync(), isTrue);
        expect(store.file.readAsStringSync(), recorded);
        verify(
          () => logger.info(
            'Nothing to remove for Gemini: VGV AI CLI has not configured it.',
          ),
        ).called(1);
        verify(() => logger.info(sharedStillPresent)).called(1);
        verifyNever(
          () => logger.info('Nothing to remove for the selected harnesses.'),
        );
      });

      test('says when no recorded harness is selected', () async {
        final exitCode = await runUninstall(['--no-codex', '--no-pi']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(codexFile).existsSync(), isTrue);
        verify(
          () => logger.info('Nothing to remove for the selected harnesses.'),
        ).called(1);
      });

      test('removes the shared skills when only they are recorded', () async {
        store.save(InstallManifest(store.load()!.entriesFor(null)));

        final exitCode = await runUninstall(['--no-codex']);

        expect(exitCode, ExitCode.success.code);
        expect(homeFile(sharedSkill).existsSync(), isFalse);
        expect(store.file.existsSync(), isFalse);
      });

      test('--only help does not mention detection', () {
        final command = UninstallCommand(logger: logger);

        expect(
          command.argParser.options['only']!.help,
          'Remove just these '
          'harnesses.',
        );
      });
    });

    group('shared skills and empty directories', () {
      const sharedRemoved =
          'The skills in /home/dev/.agents/skills were installed by VGV AI CLI '
          'and are shared by all your coding agents, so they are being '
          'removed.';

      Directory homeDirectory(String relativePath) =>
          fs.directory(fs.path.join(home.path, relativePath));

      test('a full uninstall removes the skill directories', () async {
        install([
          owned(null, '.agents/skills/a/SKILL.md'),
          owned(null, '.agents/skills/a/references/guide.md'),
          owned(null, '.agents/skills/b/scripts/run.sh'),
        ]);

        await runUninstall();

        expect(homeDirectory('.agents/skills').listSync(), isEmpty);
        verify(() => logger.info(sharedRemoved)).called(1);
      });

      test(
        'says nothing of the shared skills when none are recorded',
        () async {
          install([owned(Harness.codex, '.codex/AGENTS.md')]);

          await runUninstall();

          verifyNever(() => logger.info(sharedRemoved));
        },
      );

      test('removes the harness directories it empties, not the config '
          'root', () async {
        seed('.gemini/settings.json', '{}');
        install([
          owned(Harness.gemini, '.gemini/commands/vgv/a.toml'),
          owned(Harness.pi, '.pi/agent/prompts/a.md'),
        ]);

        await runUninstall();

        expect(homeDirectory('.gemini/commands').existsSync(), isFalse);
        expect(homeDirectory('.gemini').existsSync(), isTrue);
        expect(homeDirectory('.pi/agent/prompts').existsSync(), isFalse);
        expect(homeDirectory('.pi/agent').existsSync(), isTrue);
      });

      test('keeps a directory that still holds a file of the user', () async {
        install([owned(null, '.agents/skills/a/SKILL.md')]);
        final notes = seed('.agents/skills/a/notes.md', 'mine');

        await runUninstall();

        expect(notes.existsSync(), isTrue);
      });

      test(
        'keeps the directory of a file that was only partly removed',
        () async {
          install([owned(null, '.agents/skills/a/SKILL.md')]);
          homeFile('.agents/skills/a/SKILL.md').writeAsStringSync('edited');

          await runUninstall();

          expect(homeFile('.agents/skills/a/SKILL.md').existsSync(), isTrue);
        },
      );

      test('warns when an empty directory cannot be deleted', () async {
        install([owned(null, '.agents/skills/a/SKILL.md')]);
        undeletable = homeDirectory('.agents/skills/a').path;

        final exitCode = await runUninstall();

        expect(exitCode, ExitCode.success.code);
        expect(homeFile('.agents/skills/a/SKILL.md').existsSync(), isFalse);
        verify(
          () => logger.warn(
            'Could not delete the empty directories above '
            '${homeFile('.agents/skills/a/SKILL.md').path}: Cannot delete',
          ),
        ).called(1);
      });
    });

    group('--check', () {
      /// Every path under the root, with the contents of each file.
      Map<String, String> snapshot() => {
        for (final entity in fs.directory('/').listSync(recursive: true))
          entity.path: entity is File ? entity.readAsStringSync() : '',
      };

      setUp(
        () => install([
          owned(null, '.agents/skills/a/SKILL.md'),
          owned(Harness.codex, '.codex/agents/a.toml'),
          owned(Harness.pi, '.pi/agent/AGENTS.md'),
        ]),
      );

      test('removes nothing, not even from the manifest', () async {
        final before = snapshot();

        final exitCode = await runUninstall(['--check']);

        expect(exitCode, ExitCode.success.code);
        expect(snapshot(), before);
      });

      test('lists what would be removed and ends with a note', () async {
        await runUninstall(['--check']);

        verifyInOrder([
          () => logger.info(
            'The skills in /home/dev/.agents/skills were installed by VGV AI '
            'CLI and are shared by all your coding agents, so they would be '
            'removed.',
          ),
          () => logger.info(
            'Would remove ${homeFile('.agents/skills/a/SKILL.md').path}',
          ),
          () => logger.info(
            'Would remove ${homeFile('.codex/agents/a.toml').path}',
          ),
          () => logger.info(
            'Would remove ${homeFile('.pi/agent/AGENTS.md').path}',
          ),
          () => logger.info(
            '\n${lightYellow.wrap('--check')} so nothing was removed.',
          ),
        ]);
      });

      test('lists only what a selection would remove', () async {
        await runUninstall(['--check', '--only', 'codex']);

        verify(
          () => logger.info(
            'Would remove ${homeFile('.codex/agents/a.toml').path}',
          ),
        ).called(1);
        verifyNever(
          () => logger.info(any(that: contains('.pi/agent/AGENTS.md'))),
        );
        verifyNever(() => logger.info(any(that: contains('a/SKILL.md'))));
      });
    });

    group('manifest', () {
      test('keeps what is left to remove', () async {
        install([
          owned(Harness.codex, '.codex/AGENTS.md'),
          owned(Harness.pi, '.pi/agent/AGENTS.md'),
        ]);
        homeFile('.pi/agent/AGENTS.md').writeAsStringSync('edited');

        await runUninstall();

        expect(store.load()!.entries.map((entry) => entry.owner), [Harness.pi]);
      });

      test('removes nothing over one from a newer version', () async {
        final newer = jsonEncode({'version': InstallManifest.version + 1});
        store.file
          ..createSync(recursive: true)
          ..writeAsStringSync(newer);

        final exitCode = await runUninstall();

        expect(exitCode, ExitCode.ioError.code);
        expect(store.file.readAsStringSync(), newer);
        verify(
          () => logger.err(
            'Removed nothing, because ${ManifestStore.unreadable}: '
            '${store.file.path}',
          ),
        ).called(1);
      });

      test('removes nothing when it cannot be read', () async {
        store.file
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe]);

        final exitCode = await runUninstall();

        expect(exitCode, ExitCode.ioError.code);
        verify(
          () => logger.err(
            any(
              that: startsWith(
                'Removed nothing, because ${store.file.path} could not be '
                'read: ',
              ),
            ),
          ),
        ).called(1);
      });

      test('exits with an I/O error when it cannot be saved', () async {
        install([
          owned(Harness.codex, '.codex/AGENTS.md'),
          owned(Harness.pi, '.pi/agent/AGENTS.md'),
        ]);
        homeFile('.pi/agent/AGENTS.md').writeAsStringSync('edited');
        // Replacing the manifest goes through a temporary file, which a
        // directory in its place blocks.
        fs.directory('${store.file.path}.vgv-tmp').createSync();

        final exitCode = await runUninstall();

        expect(exitCode, ExitCode.ioError.code);
        verify(
          () => logger.err(
            any(
              that: startsWith(
                'Could not record what was removed in ${store.file.path}: ',
              ),
            ),
          ),
        ).called(1);
      });
    });

    group('the home directory', () {
      test('comes from the environment', () async {
        final exitCode = await runThroughRunner(
          UninstallCommand(
            logger: logger,
            environment: {'HOME': '/nowhere/${DateTime.now().microsecond}'},
          ),
          const [],
        );

        expect(exitCode, ExitCode.success.code);
      });

      test('is a config error when it cannot be found', () async {
        final exitCode = await runThroughRunner(
          UninstallCommand(logger: logger, environment: const {}),
          const [],
        );

        expect(exitCode, ExitCode.config.code);
        verify(
          () => logger.err(any(that: contains('Could not find your home'))),
        ).called(1);
      });
    });
  });
}
