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

/// A [ManifestAuditor] that reports [unreadable] as unreadable, and verifies
/// everything else for real.
class _LockedAuditor extends ManifestAuditor {
  const new(this.unreadable);

  final String unreadable;

  @override
  EntryHealth verify(ManifestEntry entry, FileSystem fileSystem) =>
      entry.path == unreadable
      ? EntryHealth.unreadable(entry, error: 'Permission denied')
      : super.verify(entry, fileSystem);
}

void main() {
  group('doctor', () {
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

    Future<int> runThroughRunner(DoctorCommand command, List<String> args) =>
        VgvAiCliCommandRunner(
          logger: logger,
          pubUpdater: pubUpdater,
          doctorCommand: command,
        ).run(['doctor', ...args]);

    Future<int> runDoctor({ManifestAuditor? auditor}) => runThroughRunner(
      DoctorCommand(
        logger: logger,
        home: home,
        auditor: auditor ?? const ManifestAuditor(),
      ),
      const [],
    );

    File homeFile(String relative) =>
        fs.file(fs.path.join(home.path, relative));

    /// Installs [changes] with the real reconciler, as `install` does.
    void install(List<PlannedChange> changes) => store.save(
      const Reconciler().apply(changes, manifest: store.load()!).manifest,
    );

    PlannedChange owned(String relative, {Harness? harness}) =>
        PlannedChange.text(
          file: homeFile(relative),
          contents: 'vgv',
          harness: harness,
        );

    PlannedChange json(String relative, Object contents, Harness harness) =>
        PlannedChange.text(
          file: homeFile(relative),
          contents: jsonEncode(contents),
          harness: harness,
          mode: ChangeMode.mergeJson,
        );

    /// Every file under the in-memory root, by path, to prove nothing is
    /// written.
    Map<String, String> snapshot() => {
      for (final entity in fs.directory('/').listSync(recursive: true))
        if (entity is File) entity.path: entity.readAsStringSync(),
    };

    void verifyInfo(String message) =>
        verify(() => logger.info(message)).called(1);

    test('reports an intact install per owner and exits 0', () async {
      install([
        owned('.agents/skills/a/SKILL.md'),
        owned('.codex/agents/a.toml', harness: Harness.codex),
      ]);

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.success.code);
      verifyInfo('✓ Shared');
      verifyInfo('✓ Codex');
    });

    test('reports nothing installed when there is no manifest', () async {
      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.success.code);
      expect(store.file.existsSync(), isFalse);
      verifyInfo(
        "VGV hasn't installed anything here yet. Run vgv_ai install to set "
        'it up.',
      );
    });

    test('reports a missing file with its install fix', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
      homeFile('.codex/agents/a.toml').deleteSync();

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('✗ Codex');
      verifyInfo('    missing ~/.codex/agents/a.toml');
      verifyInfo('      vgv_ai install --only codex');
    });

    test('reports a changed file with its forced install fix', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);
      homeFile('.codex/agents/a.toml').writeAsStringSync('mine');

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    changed ~/.codex/agents/a.toml');
      verifyInfo('      vgv_ai install --only codex --force');
    });

    test('names the keys that are missing or changed', () async {
      install([
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
        json('.opencode/opencode.json', {'model': 'vgv'}, Harness.opencode),
      ]);
      homeFile('.gemini/settings.json').writeAsStringSync('{}');
      homeFile('.opencode/opencode.json')
          .writeAsStringSync(jsonEncode({'model': 'mine'}));

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    missing ~/.gemini/settings.json: theme');
      verifyInfo('    changed ~/.opencode/opencode.json: model');
    });

    test('reports a file it cannot parse with a manual step', () async {
      install([
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
      ]);
      homeFile('.gemini/settings.json').writeAsStringSync('{ not json');

      final exitCode = await runDoctor();

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    cannot parse ~/.gemini/settings.json');
      verifyInfo('      Fix its syntax, then run vgv_ai install.');
    });

    test('reports a file it cannot read with a manual step', () async {
      install([owned('.codex/agents/a.toml', harness: Harness.codex)]);

      final exitCode = await runDoctor(
        auditor: _LockedAuditor(homeFile('.codex/agents/a.toml').path),
      );

      expect(exitCode, ExitCode.software.code);
      verifyInfo('    cannot read ~/.codex/agents/a.toml: Permission denied');
      verifyInfo('      Check that you can read it, then run doctor again.');
    });

    test(
      'fixes shared skills through the configured harnesses that read them',
      () async {
        install([
          owned('.agents/skills/a/SKILL.md'),
          owned('.claude/a.md', harness: Harness.claude),
          owned('.codex/agents/a.toml', harness: Harness.codex),
          owned('.gemini/agents/a.md', harness: Harness.gemini),
        ]);
        homeFile('.agents/skills/a/SKILL.md').deleteSync();

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verifyInfo('✗ Shared');
        verifyInfo('    missing ~/.agents/skills/a/SKILL.md');
        verifyInfo('      vgv_ai install --only gemini --only codex');
        verifyInfo('✓ Claude Code');
      },
    );

    test('writes nothing, whatever it finds', () async {
      install([
        owned('.agents/skills/a/SKILL.md'),
        owned('.codex/agents/a.toml', harness: Harness.codex),
        json('.gemini/settings.json', {'theme': 'vgv'}, Harness.gemini),
      ]);
      homeFile('.agents/skills/a/SKILL.md').deleteSync();
      homeFile('.codex/agents/a.toml').writeAsStringSync('mine');
      homeFile('.gemini/settings.json').writeAsStringSync('{ not json');
      final before = snapshot();

      await runDoctor();

      expect(snapshot(), before);
    });

    group('the manifest', () {
      test('from another version exits 70 with a manual step', () async {
        final newer = jsonEncode({'version': InstallManifest.version + 1});
        store.file
          ..createSync(recursive: true)
          ..writeAsStringSync(newer);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        expect(store.file.readAsStringSync(), newer);
        verify(
          () => logger.err(
            '${store.file.path} was written by another version of vgv_ai.',
          ),
        ).called(1);
        verifyInfo(
          'Run vgv_ai update, or move it aside and run vgv_ai install.',
        );
      });

      test('that cannot be read exits 70 with a manual step', () async {
        store.file
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xff, 0xfe]);

        final exitCode = await runDoctor();

        expect(exitCode, ExitCode.software.code);
        verify(
          () => logger.err(
            any(that: startsWith('Could not read ${store.file.path}: ')),
          ),
        ).called(1);
        verifyInfo('Check that you can read it, then run doctor again.');
      });
    });

    test('describes itself', () {
      final command = DoctorCommand(logger: logger);

      expect(command.name, 'doctor');
      expect(command.description, isNotEmpty);
    });

    group('the home directory', () {
      test('comes from the environment', () async {
        final exitCode = await runThroughRunner(
          DoctorCommand(
            logger: logger,
            environment: {'HOME': '/nowhere/${DateTime.now().microsecond}'},
          ),
          const [],
        );

        expect(exitCode, ExitCode.success.code);
        verifyInfo(
          "VGV hasn't installed anything here yet. Run vgv_ai install to "
          'set it up.',
        );
      });

      test('is a config error when it cannot be found', () async {
        final exitCode = await runThroughRunner(
          DoctorCommand(logger: logger, environment: const {}),
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
