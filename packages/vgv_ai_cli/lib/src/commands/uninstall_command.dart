import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template uninstall_command}
/// Takes back what the install manifest proves VGV wrote, and nothing else.
/// {@endtemplate}
class UninstallCommand extends Command<int> {
  /// {@macro uninstall_command}
  new({
    required this._logger,
    this._home,
    this._environment,
    this._auditor = const ManifestAuditor(),
  });

  final Logger _logger;
  final Directory? _home;
  final Map<String, String>? _environment;
  final ManifestAuditor _auditor;

  static const String commandName = 'uninstall';

  @override
  String get description =>
      'Remove the Very Good AI tooling installed for your coding agents.';

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final home = _home ?? userHome(_environment ?? Platform.environment);
    if (home == null) {
      _logger.err(
        'Could not find your home directory. Set HOME and run uninstall '
        'again.',
      );
      return ExitCode.config.code;
    }

    final store = ManifestStore(home);
    final manifest = _load(store);
    if (manifest == null) return ExitCode.ioError.code;
    if (manifest.entries.isEmpty) {
      _logger.info(
        "VGV AI CLI hasn't installed anything here, so there is nothing to "
        'remove.',
      );
      return ExitCode.success.code;
    }

    final reversal = _auditor.reverse(manifest, home.fileSystem);
    _report(reversal.entries);

    final recorded = _record(store, from: manifest, to: reversal.manifest);
    final anyFailed = reversal.entries.any(
      (entry) => entry.outcome == ReverseOutcome.failed,
    );
    return !recorded || anyFailed
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// The manifest in [store], or null, having said why, when it cannot be
  /// read or was written by a newer version.
  InstallManifest? _load(ManifestStore store) {
    try {
      final manifest = store.load();
      if (manifest == null) {
        _logger.err(
          'Removed nothing, because ${ManifestStore.unreadable}: '
          '${store.file.path}',
        );
      }
      return manifest;
    } on FileSystemException catch (error) {
      _logger.err(
        'Removed nothing, because ${store.file.path} could not be read: '
        '${error.description}',
      );
      return null;
    }
  }

  /// Saves [to] in [store] unless it is [from], and returns whether it could.
  bool _record(
    ManifestStore store, {
    required InstallManifest from,
    required InstallManifest to,
  }) {
    if (to == from) return true;

    try {
      store.save(to);
      return true;
    } on FileSystemException catch (error) {
      _logger.err(
        'Could not record what was removed in ${store.file.path}: '
        '${error.description}',
      );
      return false;
    }
  }

  /// Reports what reversing each of [entries] did.
  void _report(List<ReversedEntry> entries) {
    for (final ReversedEntry(:entry, :outcome, :error) in entries) {
      final path = entry.path;
      switch (outcome) {
        case ReverseOutcome.removed:
          _logger.detail('Removed $path');
        case ReverseOutcome.failed:
          _logger.err('Could not update $path: $error');
        case _:
      }
    }
  }
}
