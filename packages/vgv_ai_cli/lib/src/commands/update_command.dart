import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart' show Directory;
import 'package:mason_logger/mason_logger.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/install_command.dart';
import 'package:vgv_ai_cli/src/commands/installation.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/version.dart';

/// {@template update_command}
/// Updates `vgv_ai` to the latest version on pub.dev, then reinstalls the
/// harnesses and plugins a previous `install` wrote, at the new pins.
///
/// An installation other than [Installation.pub] is not updated: the command
/// prints its [Installation.upgradeCommand] instead.
/// {@endtemplate}
class UpdateCommand({
  required final Logger _logger,
  PubUpdater? pubUpdater,
  Installation? installation,
  final Directory? _home,
  final Map<String, String>? _environment,
  final StartProcess _startProcess = Process.start,
}) extends Command<int> {
  /// {@macro update_command}
  ///
  /// [installation] defaults to [Installation.current].
  this;

  final PubUpdater _pubUpdater = pubUpdater ?? PubUpdater();
  final Installation _installation = installation ?? Installation.current;

  @override
  String get description => 'Update vgv_ai to the latest version.';

  /// The name the CLI registers `update` under, so other code can name it
  /// without constructing one. The runner skips its update check for it.
  static const String commandName = 'update';

  @override
  String get name => commandName;

  /// What the user runs to move installed plugins to the new pins.
  static final String reinstallHint =
      'Then run ${lightCyan.wrap('$executableName install')} '
      'to update your installed plugins.';

  @override
  Future<int> run() async {
    final updateCheckProgress = _logger.progress('Checking for updates');
    late final String latestVersion;
    try {
      latestVersion = await _pubUpdater.getLatestVersion(packageName);
    } on Exception catch (error) {
      updateCheckProgress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
    updateCheckProgress.complete('Checked for updates');

    final isUpToDate = packageVersion == latestVersion;
    if (isUpToDate) {
      _logger.info('CLI is already at the latest version.');
      return ExitCode.success.code;
    }

    if (_installation != Installation.pub) {
      _logger
        ..info(
          '$executableName $latestVersion is available. '
          'Run ${_installation.upgradeCommand} to update.',
        )
        ..info(reinstallHint);
      return ExitCode.success.code;
    }

    final updated = await _update(latestVersion);
    if (!updated) return ExitCode.software.code;

    return _wasInstalled ? await _reinstall() : ExitCode.success.code;
  }

  /// Updates the CLI to [latestVersion], and returns whether it could.
  Future<bool> _update(String latestVersion) async {
    final updateProgress = _logger.progress('Updating to $latestVersion');

    late final ProcessResult result;
    try {
      result = await _pubUpdater.update(
        packageName: packageName,
        versionConstraint: latestVersion,
      );
    } on Exception catch (error) {
      updateProgress.fail();
      _logger.err('$error');
      return false;
    }

    if (result.exitCode != ExitCode.success.code) {
      updateProgress.fail();
      _logger.err('Error updating CLI: ${result.stderr}');
      return false;
    }

    updateProgress.complete('Updated to $latestVersion');
    return true;
  }

  /// Whether a previous `install` left a manifest behind.
  bool get _wasInstalled {
    final home = commandHome(_home, _environment);
    return home != null && ManifestStore(home).file.existsSync();
  }

  /// Runs `install --refresh` from the version just activated, which
  /// carries the new pins, for the harnesses and plugins installed before.
  Future<int> _reinstall() async {
    _logger.info('Updating your installed plugins...');
    try {
      final process = await _startProcess(Platform.resolvedExecutable, [
        'pub',
        'global',
        'run',
        '$packageName:$executableName',
        if (globalResults?['verbose'] == true) '--verbose',
        InstallCommand.commandName,
        '--${InstallCommand.refreshFlag}',
      ], mode: ProcessStartMode.inheritStdio);
      return await process.exitCode;
    } on ProcessException catch (error) {
      _logger
        ..err('Could not update your installed plugins: ${error.message}')
        ..info(reinstallHint);
      return ExitCode.software.code;
    }
  }
}
