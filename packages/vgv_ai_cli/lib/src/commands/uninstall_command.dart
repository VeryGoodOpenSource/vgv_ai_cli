import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template uninstall_command}
/// Takes back what the install manifest proves VGV wrote, and nothing else.
///
/// The harnesses come from the manifest, never from detection, so a harness
/// that was uninstalled since can still be cleaned up.
///
/// * `--check` prints what would be removed without removing anything.
/// * `--force` also removes what VGV wrote that you have changed since.
/// * `--only` removes just the named harnesses.
/// * `--no-<harness>` keeps one harness. It cannot be combined with `--only`.
///
/// The shared skills are removed only when every harness the manifest
/// records is, since the harnesses that are left still read them.
/// {@endtemplate}
class UninstallCommand extends Command<int> with HarnessSelection {
  /// {@macro uninstall_command}
  new({
    required this._logger,
    this._home,
    this._environment,
    this._auditor = const ManifestAuditor(),
  }) {
    argParser
      ..addFlag(
        'check',
        help: 'Print what would be removed without removing anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help: 'Also remove what install wrote that you have changed since.',
        negatable: false,
      );
    addHarnessOptions('Remove', only: 'just these harnesses.');
  }

  final Logger _logger;
  final Directory? _home;
  final Map<String, String>? _environment;
  final ManifestAuditor _auditor;

  static const String commandName = 'uninstall';

  /// The outcomes where something the user changed was kept.
  static const Set<ReverseOutcome> _kept = {
    ReverseOutcome.partial,
    ReverseOutcome.skipped,
  };

  /// The outcomes that take something of VGV's out of a file.
  static const Set<ReverseOutcome> _changed = {
    ReverseOutcome.removed,
    ReverseOutcome.partial,
  };

  @override
  String get description =>
      'Remove the Very Good AI tooling installed for your coding agents.';

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final dryRun = argResults!['check'] == true;
    final force = argResults!['force'] == true;
    final only = onlyHarnesses;
    final selected = only ?? Harness.values.where(isEnabled).toSet();

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

    final recorded = {for (final entry in manifest.entries) ?entry.owner};
    for (final harness in (only ?? const {}).difference(recorded)) {
      _logger.info(
        'Nothing to remove for ${harness.displayName}: VGV AI CLI has not '
        'configured it.',
      );
    }

    // The harnesses left behind still read the shared skills, so they go
    // only with the last of them.
    final full = selected.containsAll(recorded);
    final owners = {...recorded.intersection(selected), if (full) null};
    final hasSharedSkills = manifest.entriesFor(null).isNotEmpty;
    final skillsRoot = agentsSkillsRoot(home);
    if (full && hasSharedSkills) {
      _logger.info(
        'The skills in ${skillsRoot.path} were installed by VGV '
        'AI CLI and are shared by all your coding agents, so they '
        '${dryRun ? 'would be' : 'are being'} removed.',
      );
    }
    final reversal = _auditor.reverse(
      manifest,
      home.fileSystem,
      owners: owners,
      force: force,
      dryRun: dryRun,
    );
    _report(reversal.entries, dryRun: dryRun);
    if (!dryRun) _deleteEmptyDirectories(reversal.entries, home);
    if (reversal.entries.isEmpty && only == null) {
      _logger.info('Nothing to remove for the selected harnesses.');
    }
    if (!full && hasSharedSkills) {
      _logger.info(
        'The shared skills VGV AI CLI installed are still in '
        '${skillsRoot.path}. Run '
        "${lightCyan.wrap('vgv_ai uninstall')} with no flags to remove them.",
      );
    }
    if (reversal.entries.any((entry) => _changed.contains(entry.outcome))) {
      _logger.info(
        dryRun
            ? '\n${lightYellow.wrap('--check')} so nothing was removed.'
            : '\nRestart your coding agents to pick up the changes.',
      );
    }

    final saved =
        dryRun || _record(store, from: manifest, to: reversal.manifest);
    final anyFailed = reversal.entries.any(
      (entry) => entry.outcome == ReverseOutcome.failed,
    );
    return !saved || anyFailed ? ExitCode.ioError.code : ExitCode.success.code;
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

  /// Deletes the directories each removed entry of [entries] left empty, up
  /// to the skills root for the shared skills and the harness's config
  /// directory for the rest, which are never deleted.
  ///
  /// The files are already gone by now, so a directory that cannot be
  /// deleted is only warned about.
  void _deleteEmptyDirectories(List<ReversedEntry> entries, Directory home) {
    final fileSystem = home.fileSystem;
    for (final ReversedEntry(:entry, :outcome) in entries) {
      if (outcome != ReverseOutcome.removed) continue;

      try {
        fileSystem
            .file(entry.path)
            .parent
            .deleteEmptyUpTo(
              entry.owner?.configDirectory(home) ?? agentsSkillsRoot(home),
            );
      } on FileSystemException catch (error) {
        _logger.warn(
          'Could not delete the empty directories above ${entry.path}: '
          '${error.description}',
        );
      }
    }
  }

  /// Reports what reversing each of [entries] did, and what [dryRun] means
  /// for the files.
  void _report(List<ReversedEntry> entries, {required bool dryRun}) {
    for (final ReversedEntry(:entry, :outcome, :error) in entries) {
      final path = entry.path;
      switch (outcome) {
        case ReverseOutcome.failed:
          _logger.err('Could not update $path: $error');
        case ReverseOutcome.unparseable:
          _logger.warn('Left $path alone because it could not be parsed.');
        case ReverseOutcome.missing:
          _logger.detail('$path was already gone');
        // A dry run exists to show what would be removed, so its paths are
        // always printed.
        case ReverseOutcome.removed || ReverseOutcome.partial when dryRun:
          _logger.info('Would remove $path');
        case ReverseOutcome.removed || ReverseOutcome.partial:
          _logger.detail('Removed $path');
        // Reported with the other kept changes below.
        case ReverseOutcome.skipped:
      }
    }

    final kept = entries.where((entry) => _kept.contains(entry.outcome));
    for (final ReversedEntry(:entry) in kept) {
      _logger.warn('Kept your changes in ${entry.path}');
    }
    if (kept.isNotEmpty) {
      _logger.info('Pass ${lightCyan.wrap('--force')} to remove them too.');
    }
  }
}
