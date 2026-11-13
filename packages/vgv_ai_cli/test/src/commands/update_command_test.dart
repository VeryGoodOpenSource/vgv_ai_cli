import 'dart:io';

import 'package:file/file.dart' show Directory;
import 'package:file/memory.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/version.dart';

import '../../helpers/test_runner.dart';

class _MockProcess extends Mock implements Process;

/// One call to the injected `startProcess`.
class _Start(
  final String executable,
  final List<String> arguments,
  final ProcessStartMode mode,
);

void main() {
  group(UpdateCommand, () {
    const latestVersion = '0.0.0';
    const runNewVersion = ['pub', 'global', 'run', 'vgv_ai_cli:vgv_ai'];

    late PubUpdater pubUpdater;
    late Logger logger;
    late TestRunner runner;
    late Directory home;
    late Process process;
    late List<_Start> started;
    late VgvAiCliCommandRunner commandRunner;

    Future<Process> startProcess(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode = ProcessStartMode.normal,
    }) async {
      started.add(_Start(executable, arguments, mode));
      return process;
    }

    UpdateCommand updateCommand({
      Directory? home,
      Map<String, String>? environment,
    }) => UpdateCommand(
      logger: logger,
      pubUpdater: pubUpdater,
      installation: Installation.pub,
      home: home,
      environment: environment,
      startProcess: startProcess,
    );

    void recordInstall() => ManifestStore(home).file
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');

    setUp(() {
      runner = TestRunner();
      pubUpdater = runner.pubUpdater;
      logger = runner.logger;
      home = MemoryFileSystem.test().directory('/home/dev')
        ..createSync(recursive: true);
      process = _MockProcess();
      when(() => process.exitCode).thenAnswer((_) async => 0);
      started = [];
      commandRunner = runner.build(updateCommand: updateCommand(home: home));

      when(
        () => pubUpdater.update(
          packageName: packageName,
          versionConstraint: latestVersion,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, ExitCode.success.code, null, null),
      );
    });

    test('can be instantiated without a pub updater', () {
      final command = UpdateCommand(logger: logger);
      expect(command, isNotNull);
    });

    test('handles pub latest version query errors', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenThrow(Exception('oops'));
      final result = await commandRunner.run(['update']);
      expect(result, ExitCode.software.code);
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Exception: oops'));
      verifyNever(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      );
    });

    test('handles pub update errors', () async {
      recordInstall();
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => latestVersion);
      when(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenThrow(Exception('oops'));
      final result = await commandRunner.run(['update']);
      expect(result, ExitCode.software.code);
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Exception: oops'));
      verify(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).called(1);
      expect(started, isEmpty);
    });

    test('handles pub update process errors', () async {
      const error = 'Oh no! Installing this is not possible right now!';
      recordInstall();

      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => latestVersion);

      when(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, null, error));

      final result = await commandRunner.run(['update']);

      expect(result, ExitCode.software.code);
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Error updating CLI: $error'));
      verify(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).called(1);
      expect(started, isEmpty);
    });

    group('when newer version exists', () {
      setUp(() {
        when(() => pubUpdater.getLatestVersion(any()))
            .thenAnswer((_) async => latestVersion);
      });

      test('updates', () async {
        final result = await commandRunner.run(['update']);
        expect(result, ExitCode.success.code);
        verify(() => logger.progress('Checking for updates')).called(1);
        verify(() => logger.progress('Updating to $latestVersion')).called(1);
        verify(
          () => pubUpdater.update(
            packageName: packageName,
            versionConstraint: latestVersion,
          ),
        ).called(1);
      });

      test('reinstalls with the updated version after an install', () async {
        recordInstall();
        final result = await commandRunner.run(['update']);
        expect(result, ExitCode.success.code);
        verify(() => logger.info('Updating your installed plugins...'))
            .called(1);
        final start = started.single;
        expect(start.executable, Platform.resolvedExecutable);
        expect(start.arguments, [...runNewVersion, 'install', '--refresh']);
        expect(start.mode, ProcessStartMode.inheritStdio);
      });

      test('reinstalls verbosely when updating verbosely', () async {
        recordInstall();
        await commandRunner.run(['--verbose', 'update']);
        expect(started.single.arguments, [
          ...runNewVersion,
          '--verbose',
          'install',
          '--refresh',
        ]);
      });

      test('returns the exit code of the reinstall', () async {
        recordInstall();
        when(() => process.exitCode)
            .thenAnswer((_) async => ExitCode.usage.code);
        final result = await commandRunner.run(['update']);
        expect(result, ExitCode.usage.code);
      });

      test('reports a reinstall that cannot start', () async {
        recordInstall();
        final result = await runner.run(
          ['update'],
          updateCommand: UpdateCommand(
            logger: logger,
            pubUpdater: pubUpdater,
            installation: Installation.pub,
            home: home,
            startProcess: (executable, arguments, {mode = .normal}) =>
                throw const ProcessException('dart', [], 'not found'),
          ),
        );
        expect(result, ExitCode.software.code);
        verify(
          () =>
              logger.err('Could not update your installed plugins: not found'),
        ).called(1);
        verify(() => logger.info(UpdateCommand.reinstallHint)).called(1);
      });

      test('does not reinstall without an install', () async {
        final result = await commandRunner.run(['update']);
        expect(result, ExitCode.success.code);
        expect(started, isEmpty);
      });

      test('does not reinstall without a home directory', () async {
        final result = await runner.run([
          'update',
        ], updateCommand: updateCommand(environment: const {}));
        expect(result, ExitCode.success.code);
        expect(started, isEmpty);
      });
    });

    for (final installation in [Installation.homebrew, Installation.script]) {
      group('installed with ${installation.name}', () {
        test('prints the upgrade command instead of updating', () async {
          when(() => pubUpdater.getLatestVersion(any()))
              .thenAnswer((_) async => latestVersion);
          final result = await runner.run([
            'update',
          ], installation: installation);
          expect(result, ExitCode.success.code);
          verify(
            () => logger.info(
              '$executableName $latestVersion is available. '
              'Run ${installation.upgradeCommand} to update.',
            ),
          ).called(1);
          verify(() => logger.info(UpdateCommand.reinstallHint)).called(1);
          verifyNever(() => logger.progress('Updating to $latestVersion'));
          verifyNever(
            () => pubUpdater.update(
              packageName: any(named: 'packageName'),
              versionConstraint: any(named: 'versionConstraint'),
            ),
          );
        });

        test('does nothing when already on latest version', () async {
          final result = await runner.run([
            'update',
          ], installation: installation);
          expect(result, ExitCode.success.code);
          verify(() => logger.info('CLI is already at the latest version.'))
              .called(1);
        });
      });
    }

    test('does not update when already on latest version', () async {
      recordInstall();
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
      final result = await commandRunner.run(['update']);
      expect(result, ExitCode.success.code);
      verify(() => logger.info('CLI is already at the latest version.'))
          .called(1);
      verifyNever(() => logger.progress('Updating to $latestVersion'));
      verifyNever(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      );
      expect(started, isEmpty);
    });
  });
}
