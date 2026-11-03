import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/cli_installation.dart';
import 'package:vgv_ai_cli/src/version.dart';

/// {@template update_command}
/// Updates `vgv_ai` to the latest version on pub.dev, or, when Homebrew or
/// `install.sh` installed it, names the command that does.
/// {@endtemplate}
class UpdateCommand({
  required final Logger _logger,
  PubUpdater? pubUpdater,
  CliInstallation? installation,
}) extends Command<int> {
  /// {@macro update_command}
  ///
  /// [installation] defaults to an install from pub.dev.
  this;

  final PubUpdater _pubUpdater = pubUpdater ?? PubUpdater();
  final CliInstallation _installation =
      installation ?? const CliInstallation.pub();

  @override
  String get description => 'Update vgv_ai to the latest version.';

  /// The name the CLI registers `update` under, so other code can name it
  /// without constructing one. The runner skips its update check for it.
  static const String commandName = 'update';

  @override
  String get name => commandName;

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

    // pub.dev can only replace a CLI it installed itself. A prebuilt binary
    // is replaced the way it was installed.
    if (_installation.method != InstallMethod.pub) {
      _logger.info(
        'vgv_ai $latestVersion is available. To update, run:\n'
        '  ${lightCyan.wrap(_installation.upgradeCommand)}',
      );
      return ExitCode.success.code;
    }

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
      return ExitCode.software.code;
    }

    if (result.exitCode != ExitCode.success.code) {
      updateProgress.fail();
      _logger.err('Error updating CLI: ${result.stderr}');
      return ExitCode.software.code;
    }

    updateProgress.complete('Updated to $latestVersion');

    return ExitCode.success.code;
  }
}
