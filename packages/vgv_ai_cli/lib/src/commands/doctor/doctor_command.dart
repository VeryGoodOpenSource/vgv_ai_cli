import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template doctor_command}
/// Reports, per harness, what VGV installed that is missing, was changed
/// since, or is not what this version would install, and the `install`
/// command that fixes it.
///
/// Whether a file is current comes from a dry run of `install` against the
/// resolved plugins. When they cannot be resolved, that check is skipped and
/// the rest of the report still runs. Resolving them may clone the plugins
/// into `~/.vgv_ai/plugins`, the cache `install` reads them from too. The
/// report ends with one `install` command that fixes everything `install`
/// can.
///
/// It also suggests configuring a harness that is installed but that VGV
/// has not configured, and warns about one VGV configured that is no longer
/// installed. `--only` and `--no-<harness>` narrow the report as they
/// narrow `install`. Never writes harness config or the manifest.
/// {@endtemplate}
class DoctorCommand({
  required final Logger _logger,
  final Directory? _home,
  final Map<String, String>? _environment,
  final HarnessDetector _detector = const HarnessDetector(),
  final ManifestAuditor _auditor = const ManifestAuditor(),
  final PluginResolver _resolver = const PluginResolver(),
  final Translator _translator = const Translator(),
  final Reconciler _reconciler = const Reconciler(),
}) extends Command<int> with HarnessSelection {
  this {
    addHarnessOptions('Check');
  }

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

    final scope = onlyHarnesses ?? Harness.values.where(isEnabled).toSet();
    final detected = await _detect(scope);
    final configured = {for (final entry in manifest.entries) ?entry.owner};
    final installed = configured.intersection(scope);
    final reports = _verify(
      manifest,
      home,
      installed: installed,
      detected: detected,
      plan: installed.isEmpty
          ? ContentPlan.none()
          : await _plan(manifest, home, installed),
    )..forEach(_report);

    if (reports.isEmpty) _logger.info(_nothingToCheck(manifest));

    final fix = FixCommand.combine(reports.map((report) => report.fix));
    if (fix != null) {
      _logger
        ..info('')
        ..info('Run ${lightCyan.wrap('$fix')} to fix everything install can.');
      if (fix.force) {
        _logger.info(
          '--force applies to every harness listed, replacing your values '
          "wherever they conflict with VGV's.",
        );
      }
    }
    return reports.any((report) => report.hasProblems)
        ? ExitCode.software.code
        : ExitCode.success.code;
  }

  /// The manifest in [store], or null, having said what to do, when it
  /// cannot be read or was written by a newer version.
  InstallManifest? _load(ManifestStore store) {
    final path = store.file.path;
    try {
      final manifest = store.load();
      if (manifest == null) {
        _manual(
          Finding.manual(
            '$path was written by a newer version of vgv_ai.',
            step:
                'Run ${lightCyan.wrap('vgv_ai update')}, then run doctor '
                'again.',
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
    final detections = await Future.wait([
      for (final harness in scope)
        _detector.detect(harness).then((found) => (harness, found)),
    ]);
    return {
      for (final (harness, detection) in detections)
        if (detection.installed) harness,
    };
  }

  /// Why the report has no sections: nothing is installed yet, or nothing
  /// in scope is configured or detected.
  String _nothingToCheck(InstallManifest manifest) => manifest.entries.isEmpty
      ? "VGV AI CLI hasn't installed anything here yet. Run "
            "${lightCyan.wrap('vgv_ai install')} to set it up."
      : 'Nothing to check: no selected harness is installed on this '
            'machine or configured by VGV AI CLI.';

  /// What a dry run of `install` for [selected] would do, or an unchecked
  /// plan, having said why, when the plugins cannot be resolved.
  Future<ContentPlan> _plan(
    InstallManifest manifest,
    Directory home,
    Set<Harness> selected,
  ) async {
    final progress = _logger.progress('Resolving plugins');
    switch (await _resolver.resolve(home)) {
      case ResolvedAssets(:final assets):
        progress.complete('Resolved plugins');
        final translation = await _translator.translate(
          assets: assets,
          home: home,
          selected: selected,
        );
        return ContentPlan(
          _reconciler
              .apply(translation.changes, manifest: manifest, dryRun: true)
              .changes,
        );
      case UnavailableAssets(:final plugin, :final reasons):
        return _unchecked(progress, 'resolve $plugin', reasons);
      case UnparseableAssets(:final plugin, :final error):
        return _unchecked(progress, 'parse $plugin', ['$error']);
    }
  }

  /// An unchecked plan, having failed [progress] and listed [reasons] for
  /// why the CLI could not do [problem], such as `resolve <plugin>`.
  ContentPlan _unchecked(
    Progress progress,
    String problem,
    List<String> reasons,
  ) {
    progress.fail('Could not $problem, so content was not checked');
    for (final reason in reasons) {
      _logger.info('  - $reason');
    }
    return ContentPlan.unchecked(
      Finding.manual(
        'content not checked: could not $problem',
        step: 'Fix what Resolving plugins listed, then run doctor again.',
      ),
    );
  }

  /// The sections of the report: the plugin versions, and why content was
  /// not checked if it was not, when a harness is [installed], the shared
  /// skills when an [installed] harness reads them, and each harness that
  /// is [installed] or [detected].
  ///
  /// [installed] are the harnesses of the selected scope VGV configured, and
  /// [detected] those of it on this machine.
  List<ReportSection> _verify(
    InstallManifest manifest,
    Directory home, {
    required Set<Harness> installed,
    required Set<Harness> detected,
    required ContentPlan plan,
  }) {
    final readsShared = installed.intersection(_readShared);

    List<Finding> verifyEntries(Harness? owner) => [
      for (final entry in manifest.entriesFor(owner))
        ?_entryFinding(entry, home, plan),
      for (final path in plan.additions(owner, manifest))
        Finding.stale('new ${_display(path, home)}'),
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
            ?plan.skipped,
          ],
        ),
      if (readsShared.isNotEmpty && manifest.entriesFor(null).isNotEmpty)
        ReportSection(
          title: 'Shared',
          installs: readsShared,
          findings: verifyEntries(null),
        ),
      for (final harness in Harness.values)
        if (installed.contains(harness) || detected.contains(harness))
          ReportSection(
            title: harness.displayName,
            installs: {harness},
            findings: [
              if (!detected.contains(harness))
                const Finding.warning(
                  'not installed on this machine, but VGV AI CLI configured it',
                ),
              if (!installed.contains(harness))
                const Finding.suggestion(
                  "installed, but VGV AI CLI hasn't configured it",
                ),
              ...verifyEntries(harness),
            ],
          ),
    ];
  }

  /// What is wrong with [entry], or null when nothing is.
  ///
  /// An entry [plan] no longer installs is only worth a warning, since
  /// `install` would not put it back. One that is intact but that `install`
  /// would rewrite is stale. Otherwise its health says.
  Finding? _entryFinding(
    ManifestEntry entry,
    Directory home,
    ContentPlan plan,
  ) {
    final path = _display(entry.path, home);
    if (plan.orphans(entry)) {
      return Finding.warning(
        'orphaned $path: no longer installed by this version of VGV AI CLI',
      );
    }

    final health = _auditor.verify(entry, home.fileSystem);
    return health.status == EntryStatus.intact && plan.writes(entry.path)
        ? Finding.stale('outdated $path')
        : _finding(health, path);
  }

  /// What [health] says is wrong with the file at [path], or null when
  /// nothing is.
  Finding? _finding(EntryHealth health, String path) => switch (health.status) {
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

  /// Prints [report]'s title, each finding with any manual step, and the
  /// one `install` command that fixes the rest.
  void _report(ReportSection report) {
    final mark = switch (report) {
      ReportSection(hasProblems: true) => lightRed.wrap('✗'),
      ReportSection(hasNotices: true) => lightYellow.wrap('!'),
      _ => lightGreen.wrap('✓'),
    };
    _logger.info('$mark ${report.title}');

    for (final Finding(:message, :step) in report.findings) {
      _logger.info('    $message');
      if (step != null) _logger.info('      $step');
    }

    final fix = report.fix;
    if (fix != null) _logger.info('    Run ${lightCyan.wrap('$fix')}');
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
