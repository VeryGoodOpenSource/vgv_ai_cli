import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';
import 'package:vgv_ai_cli/src/version.dart';

class _MockLogger extends Mock implements Logger;

class _MockProgress extends Mock implements Progress;

class _MockPubUpdater extends Mock implements PubUpdater;

/// {@template test_runner}
/// The mocked collaborators a command test runs against, stubbed the way
/// every one of them needs: the CLI is already up to date, and the progress
/// [logger] hands out records its messages in [progressLogs].
///
/// Tests that need another answer re-stub [logger], [progress] or
/// [pubUpdater] themselves.
/// {@endtemplate}
class TestRunner() {
  /// {@macro test_runner}
  this {
    when(() => logger.progress(any())).thenReturn(progress);
    when(() => progress.complete(any())).thenAnswer((invocation) {
      final message = invocation.positionalArguments.first as String?;
      if (message != null) progressLogs.add(message);
    });
    when(() => pubUpdater.getLatestVersion(any()))
        .thenAnswer((_) async => packageVersion);
    when(
      () => pubUpdater.isUpToDate(
        packageName: any(named: 'packageName'),
        currentVersion: any(named: 'currentVersion'),
      ),
    ).thenAnswer((_) async => true);
  }

  /// The logger the runner and its commands write to.
  final Logger logger = _MockLogger();

  /// The progress [logger] returns.
  final Progress progress = _MockProgress();

  /// The updater the runner checks the latest version with.
  final PubUpdater pubUpdater = _MockPubUpdater();

  /// What [progress] was completed with, in order.
  final List<String> progressLogs = <String>[];

  /// A runner carrying [logger] and [pubUpdater], with the given commands
  /// replacing the ones that would otherwise reach the real home directory.
  VgvAiCliCommandRunner build({
    InstallCommand? installCommand,
    DoctorCommand? doctorCommand,
    UninstallCommand? uninstallCommand,
  }) => VgvAiCliCommandRunner(
    logger: logger,
    pubUpdater: pubUpdater,
    installCommand: installCommand,
    doctorCommand: doctorCommand,
    uninstallCommand: uninstallCommand,
  );

  /// Runs [args] through a runner from [build].
  Future<int> run(
    List<String> args, {
    InstallCommand? installCommand,
    DoctorCommand? doctorCommand,
    UninstallCommand? uninstallCommand,
  }) => build(
    installCommand: installCommand,
    doctorCommand: doctorCommand,
    uninstallCommand: uninstallCommand,
  ).run(args);
}
