import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template doctor_command}
/// Reports, per harness, what VGV installed that is missing or was changed
/// since, and the `install` command that fixes it.
///
/// It also suggests configuring a harness that is installed but that VGV
/// has not configured, and warns about one VGV configured that is no longer
/// installed. `--only` and `--no-<harness>` narrow the report as they
/// narrow `install`. Never writes harness config or the manifest.
/// {@endtemplate}
class DoctorCommand extends Command<int> with HarnessSelection {
  /// {@macro doctor_command}
  new({
    required this._logger,
    this._home,
    this._environment,
    this._detector = const HarnessDetector(),
    this._auditor = const ManifestAuditor(),
  }) {
    addHarnessOptions('Check');
  }

  final Logger _logger;
  final Directory? _home;
  final Map<String, String>? _environment;
  final HarnessDetector _detector;
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
    final home = _home ?? userHome(_environment ?? Platform.environment);
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
        "VGV AI CLI hasn't installed anything here yet. Run "
        "${lightCyan.wrap('vgv_ai install')} to set it up.",
      );
    }

    final scope = onlyHarnesses ?? Harness.values.where(isEnabled).toSet();
    final reports = _verify(
      manifest,
      home,
      scope: scope,
      detected: await _detect(scope),
    )..forEach(_report);
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

  /// The harnesses of [scope] that are installed on this machine.
  Future<Set<Harness>> _detect(Set<Harness> scope) async {
    final detections = await Future.wait(scope.map(_detector.detect));
    return {
      for (final (index, harness) in scope.indexed)
        if (detections[index].installed) harness,
    };
  }

  /// The sections of the report: the plugin versions when a harness in
  /// [scope] is configured, the shared skills when a configured harness in
  /// [scope] reads them, and each harness in [scope] that is configured or
  /// [detected].
  List<ReportSection> _verify(
    InstallManifest manifest,
    Directory home, {
    required Set<Harness> scope,
    required Set<Harness> detected,
  }) {
    final configured = {for (final entry in manifest.entries) ?entry.owner};
    final installed = configured.intersection(scope);
    final readsShared = configured
        .intersection(scope)
        .intersection(_readShared);

    List<Finding> verifyEntries(Harness? owner) => [
      for (final entry in manifest.entriesFor(owner))
        ?_finding(_auditor.verify(entry, home.fileSystem), home),
    ];

    return [
      if (installed.isNotEmpty)
        ReportSection(
          title: 'Plugins',
          installs: installed,
          findings: [
            for (final plugin in vgvPlugins)
              PluginVersion.of(
                plugin,
                installed: manifest.plugins[plugin.name],
              ).finding,
          ],
        ),
      if (readsShared.isNotEmpty && manifest.entriesFor(null).isNotEmpty)
        ReportSection(
          title: 'Shared',
          installs: readsShared,
          findings: verifyEntries(null),
        ),
      for (final harness in Harness.values)
        if (scope.contains(harness) &&
            (configured.contains(harness) || detected.contains(harness)))
          ReportSection(
            title: harness.displayName,
            installs: {harness},
            findings: [
              if (!detected.contains(harness))
                const Finding.warning(
                  'not installed on this machine, but VGV AI CLI configured it',
                ),
              if (!configured.contains(harness))
                const Finding.suggestion(
                  "installed, but VGV AI CLI hasn't configured it",
                ),
              ...verifyEntries(harness),
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

  /// Prints [report]'s title, and each finding with how to fix it.
  void _report(ReportSection report) {
    final mark = switch (report) {
      ReportSection(hasProblems: true) => lightRed.wrap('✗'),
      ReportSection(hasNotices: true) => lightYellow.wrap('!'),
      _ => lightGreen.wrap('✓'),
    };
    _logger.info('$mark ${report.title}');

    for (final finding in report.findings) {
      _logger.info('    ${finding.message}');
      final fix =
          finding.step ?? lightCyan.wrap(report.fixFor(finding)?.toString());
      if (fix != null) _logger.info('      $fix');
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
