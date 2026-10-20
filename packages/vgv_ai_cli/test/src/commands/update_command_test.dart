import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/version.dart';

import '../../helpers/command_helper.dart';

void main() {
  const latestVersion = '0.0.0';

  group('update', () {
    late PubUpdater pubUpdater;
    late Logger logger;
    late VgvAiCliCommandRunner commandRunner;

    setUp(() {
      final harness = TestRunner();
      pubUpdater = harness.pubUpdater;
      logger = harness.logger;
      commandRunner = harness.build();

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
      expect(result, equals(ExitCode.software.code));
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
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => latestVersion);
      when(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenThrow(Exception('oops'));
      final result = await commandRunner.run(['update']);
      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Exception: oops'));
      verify(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).called(1);
    });

    test('handles pub update process errors', () async {
      const error = 'Oh no! Installing this is not possible right now!';

      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => latestVersion);

      when(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, null, error));

      final result = await commandRunner.run(['update']);

      expect(result, equals(ExitCode.software.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.err('Error updating CLI: $error'));
      verify(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).called(1);
    });

    test('updates when newer version exists', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => latestVersion);
      when(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, ExitCode.success.code, null, null),
      );
      final result = await commandRunner.run(['update']);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.progress('Checking for updates')).called(1);
      verify(() => logger.progress('Updating to $latestVersion')).called(1);
      verify(
        () => pubUpdater.update(
          packageName: packageName,
          versionConstraint: latestVersion,
        ),
      ).called(1);
    });

    test('does not update when already on latest version', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);
      final result = await commandRunner.run(['update']);
      expect(result, equals(ExitCode.success.code));
      verify(() => logger.info('CLI is already at the latest version.'))
          .called(1);
      verifyNever(() => logger.progress('Updating to $latestVersion'));
      verifyNever(
        () => pubUpdater.update(
          packageName: any(named: 'packageName'),
          versionConstraint: any(named: 'versionConstraint'),
        ),
      );
    });
  });
}
