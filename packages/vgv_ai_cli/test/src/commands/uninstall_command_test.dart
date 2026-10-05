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

    setUp(() {
      logger = _MockLogger();
      pubUpdater = _MockPubUpdater();
      fs = MemoryFileSystem.test();
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
