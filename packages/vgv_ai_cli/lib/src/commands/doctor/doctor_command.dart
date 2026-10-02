import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/commands/install_command.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template doctor_command}
/// Reports, per harness, what VGV installed that is missing or was changed
/// since, and the `install` command that fixes it.
///
/// Never writes harness config or the manifest.
/// {@endtemplate}
class DoctorCommand extends Command<int> {
  /// {@macro doctor_command}
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

  static const String commandName = 'doctor';

  /// The harnesses that load the shared skills, so whose `install` fixes
  /// them.
  static final Set<Harness> _readShared = {
    for (final translator in harnessTranslators)
      if (translator.readsSharedSkills) translator.harness,
  };

  @override
  String get description =>
      'Check that the Very Good AI tooling is installed and current.';

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final home =
        _home ?? InstallCommand.userHome(_environment ?? Platform.environment);
    if (home == null) {
      _logger.err(
        'Could not find your home directory. Set HOME and run doctor again.',
      );
      return ExitCode.config.code;
    }

    final store = ManifestStore(home);
    final manifest = _load(store);
    if (manifest == null) return ExitCode.software.code;

    if (manifest.entries.isEmpty) {
      _logger.info(
        "VGV hasn't installed anything here yet. Run "
        "${lightCyan.wrap('vgv_ai install')} to set it up.",
      );
      return ExitCode.success.code;
    }

    final reports = _verify(manifest, home)..forEach(_report);
    return reports.any((report) => report.hasProblems)
        ? ExitCode.software.code
        : ExitCode.success.code;
  }

  /// The manifest in [store], or null, having said what to do, when it
  /// cannot be read or was written by another version.
  InstallManifest? _load(ManifestStore store) {
    final path = store.file.path;
    try {
      final manifest = store.load();
      if (manifest == null) {
        _manual(
          Finding.manual(
            '$path was written by another version of vgv_ai.',
            step:
                'Run ${lightCyan.wrap('vgv_ai update')}, or move it aside '
                'and run ${lightCyan.wrap('vgv_ai install')}.',
          ),
        );
      }
      return manifest;
    } on FileSystemException catch (error) {
      _manual(
        Finding.manual(
          'Could not read $path: ${error.description}',
          step: 'Check that you can read it, then run doctor again.',
        ),
      );
      return null;
    }
  }

  /// One report per owner [manifest] records, shared skills first.
  List<HarnessReport> _verify(InstallManifest manifest, Directory home) {
    final configured = {for (final entry in manifest.entries) ?entry.owner};
    return [
      for (final owner in <Harness?>[null, ...Harness.values])
        if (manifest.entriesFor(owner).isNotEmpty)
          HarnessReport(
            owner: owner,
            installs: owner == null
                ? configured.intersection(_readShared)
                : {owner},
            findings: [
              for (final entry in manifest.entriesFor(owner))
                ?_finding(_auditor.verify(entry, home.fileSystem), home),
            ],
          ),
    ];
  }

  /// What [health] says is wrong, or null when nothing is.
  Finding? _finding(EntryHealth health, Directory home) {
    final path = _display(health.entry.path, home);
    return switch (health.status) {
      EntryStatus.intact => null,
      EntryStatus.missing => Finding.missing(
        'missing $path${_keys(health.missing)}',
      ),
      EntryStatus.drifted => Finding.drifted(
        'changed $path${_keys(health.drifted)}',
      ),
      EntryStatus.unparseable => Finding.manual(
        'cannot parse $path',
        step: 'Fix its syntax, then run ${lightCyan.wrap('vgv_ai install')}.',
      ),
      EntryStatus.unreadable => Finding.manual(
        'cannot read $path: ${health.error}',
        step: 'Check that you can read it, then run doctor again.',
      ),
    };
  }

  /// Prints [report]'s owner, and each finding with how to fix it.
  void _report(HarnessReport report) {
    if (!report.hasProblems) {
      _logger.info('${lightGreen.wrap('✓')} ${report.title}');
      return;
    }

    _logger.info('${lightRed.wrap('✗')} ${report.title}');
    for (final finding in report.findings) {
      final fix = finding.step ?? lightCyan.wrap('${report.fixFor(finding)}');
      _logger
        ..info('    ${finding.message}')
        ..info('      $fix');
    }
  }

  /// Prints a [Finding.manual] that is not about any one harness.
  void _manual(Finding finding) {
    _logger
      ..err(finding.message)
      ..info(finding.step);
  }
}

/// [path] relative to [home], written as `~/...`.
String _display(String path, Directory home) =>
    '~/${p.relative(path, from: home.path)}';

/// The key paths or section names [keys] lists, after a colon, or nothing
/// when the whole file is meant.
String _keys(List<String> keys) => keys.isEmpty ? '' : ': ${keys.join(', ')}';
