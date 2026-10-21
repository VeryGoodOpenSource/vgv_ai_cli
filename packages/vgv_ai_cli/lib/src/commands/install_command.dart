import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/commands/reporting_manifest_store.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template install_command}
/// Configures the Very Good AI tooling for the detected coding-agent harnesses.
///
/// * `--check` prints the changes without writing them.
/// * `--force` takes VGV's values where they conflict with the user's.
/// * `--only` configures the named harnesses, detected or not.
/// * `--no-<harness>` skips one detected harness. It cannot be combined with
///   `--only`, which already names the set.
/// * `--plugin` installs just the named VGV plugins instead of every pinned
///   one.
/// {@endtemplate}
class InstallCommand({
  required final Logger _logger,
  final Directory? _home,
  final Map<String, String>? _environment,
  final PluginResolver _resolver = const PluginResolver(),
  final HarnessDetector _detector = const HarnessDetector(),
  final Translator _translator = const Translator(),
  final Reconciler _reconciler = const Reconciler(),
}) extends Command<int> with HarnessSelection {
  this {
    argParser
      ..addFlag(
        'check',
        help: 'Print what would be written without writing anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help:
            'Also overwrite your values that conflict with the ones install '
            'writes.',
        negatable: false,
      )
      ..addMultiOption(
        'plugin',
        help: 'Install just these VGV plugins, instead of every pinned one.',
        allowed: [for (final plugin in vgvPlugins) plugin.name],
      );
    addHarnessOptions('Configure the Very Good AI tooling for');
  }

  static const String commandName = 'install';

  /// The outcomes that leave a file with VGV's contributions in it.
  static const Set<ChangeOutcome> _wrote = {
    ChangeOutcome.created,
    ChangeOutcome.updated,
    ChangeOutcome.partial,
  };

  /// The outcomes where a value the user set won over VGV's.
  static const Set<ChangeOutcome> _keptUserValues = {
    ChangeOutcome.partial,
    ChangeOutcome.skipped,
  };

  @override
  String get description =>
      'Configure the Very Good AI tooling for your coding agents.';

  @override
  String get name => commandName;

  /// The directory install configures, or null when it cannot be found.
  Directory? get home {
    return _home ?? userHome(_environment ?? Platform.environment);
  }

  @override
  Future<int> run() async {
    final force = argResults!['force'] == true;
    final dryRun = argResults!['check'] == true;

    // Falling back to the working directory would scatter harness config
    // wherever install happened to run, so a missing home is fatal.
    final home = this.home;
    if (home == null) {
      _logger.err(
        'Could not find your home directory. Set HOME and run install again.',
      );
      return ExitCode.config.code;
    }

    final selected = await _select();
    if (selected.isEmpty) {
      _logger.err(
        'No harness selected. Install one of '
        '${Harness.values.map((harness) => harness.displayName).join(', ')}, '
        'or pass --only to name one explicitly.',
      );
      return ExitCode.usage.code;
    }

    // Loaded before anything is resolved, since a manifest this version
    // cannot read means nothing can be installed.
    final store = ReportingManifestStore(
      ManifestStore(home),
      _logger,
      nothingDone: 'Installed nothing',
      done: 'written',
    );
    final manifest = store.load();
    if (manifest == null) return ExitCode.ioError.code;

    final resolved = await _resolveAssets(home);
    if (resolved == null) return ExitCode.unavailable.code;

    final plan = await _translator.translate(
      assets: resolved.assets,
      home: home,
      selected: selected,
    );

    final reconciliation = _reconciler.apply(
      plan.changes,
      manifest: manifest,
      force: force,
      dryRun: dryRun,
    );
    final applied = reconciliation.changes;

    _report(plan, applied, dryRun: dryRun);
    final recorded =
        dryRun ||
        store.save(
          from: manifest,
          to: reconciliation.manifest.withPlugins(
            _pluginVersions(manifest, resolved.assets.plugins),
          ),
        );
    final anyChangeFailed = applied.any(
      (change) => change.outcome == ChangeOutcome.failed,
    );
    return !recorded || anyChangeFailed
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// Resolves which harnesses to configure.
  ///
  /// `--only` wins outright and bypasses detection. Otherwise every harness
  /// that is both enabled and actually installed is configured, since writing
  /// config for a harness the user does not have is noise. Only enabled
  /// harnesses are probed, since each probe may wait out a timeout.
  Future<Set<Harness>> _select() async {
    final only = onlyHarnesses;
    if (only != null) return only;

    final enabled = <Harness>[];
    for (final harness in Harness.values) {
      if (isEnabled(harness)) {
        enabled.add(harness);
      } else {
        _logger.detail('Skipping ${harness.displayName}: opted out');
      }
    }

    final detections = Map.fromIterables(
      enabled,
      await Future.wait(enabled.map(_detector.detect)),
    );
    final selected = <Harness>{};

    for (final MapEntry(key: harness, value: detection) in detections.entries) {
      if (detection.installed) {
        selected.add(harness);
      } else {
        _logger.info(
          '${lightYellow.wrap('skipped')} ${harness.displayName} '
          '(not installed)',
        );
      }
    }

    return selected;
  }

  /// The plugins `--plugin` names, or null when it names none and every
  /// pinned plugin is installed.
  Set<String>? get _selectedPlugins {
    final names = argResults!['plugin'] as List<String>;
    return names.isEmpty ? null : names.toSet();
  }

  /// The versions to record for the pinned plugins: [installed] for the ones
  /// this run wrote, and what [manifest] already records for the ones it
  /// skipped, whose files are still installed.
  Map<String, String> _pluginVersions(
    InstallManifest manifest,
    List<PluginRef> installed,
  ) {
    final written = {
      for (final plugin in installed) plugin.name: plugin.version,
    };
    return {
      for (final plugin in vgvPlugins)
        plugin.name: ?(written[plugin.name] ?? manifest.plugins[plugin.name]),
    };
  }

  /// Resolves and parses the plugins `--plugin` selects into one asset
  /// bundle, or every pinned one when it selects none.
  ///
  /// Returns `null`, having said why, when any plugin cannot be resolved or
  /// parsed.
  Future<ResolvedAssets?> _resolveAssets(Directory home) async {
    final progress = _logger.progress('Resolving plugins');

    switch (await _resolver.resolve(home, only: _selectedPlugins)) {
      case final ResolvedAssets resolved:
        progress.complete(
          'Resolved ${resolved.assets.skills.length} skills and '
          '${resolved.assets.agents.length} agents',
        );
        return resolved;
      case UnavailableAssets(:final plugin, :final reasons):
        progress.fail('Could not resolve $plugin');
        for (final reason in reasons) {
          _logger.err('  - $reason');
        }
        return null;
      case UnparseableAssets(:final plugin, :final error):
        progress.fail('Could not parse $plugin');
        _logger.err('  - $error');
        return null;
    }
  }

  /// Prints what could not be translated, the files that could not be
  /// written or kept the user's values, and then what was written per owner.
  void _report(
    TranslationPlan plan,
    List<AppliedChange> applied, {
    required bool dryRun,
  }) {
    _reportNotes(plan);
    _reportOutcomes(applied, dryRun: dryRun);
    _reportKept(applied);
    _reportWritten(applied, dryRun: dryRun);
  }

  /// Warns about everything that could not be translated, per owner.
  void _reportNotes(TranslationPlan plan) {
    for (final note in plan.shared?.notes ?? const <TranslationNote>[]) {
      _logger.warn('${_ownerName(null)}: $note');
    }
    for (final MapEntry(key: harness, value: result)
        in plan.harnesses.entries) {
      for (final note in result.notes) {
        _logger.warn('${_ownerName(harness)}: $note');
      }
    }
  }

  /// Reports each file that failed, could not be parsed, or was written.
  void _reportOutcomes(List<AppliedChange> applied, {required bool dryRun}) {
    for (final AppliedChange(:change, :outcome, :error) in applied) {
      final path = change.file.path;
      switch (outcome) {
        case ChangeOutcome.failed:
          _logger.err('Could not update $path: $error');
        case ChangeOutcome.unparseable:
          _logger.warn(
            'Left $path alone because it could not be parsed. If it has '
            "comments, add VGV's settings to it by hand.",
          );
        // A dry run exists to show what would change, so its paths are
        // always printed.
        case _ when _wrote.contains(outcome) && dryRun:
          _logger.info('Would write $path');
        case _ when _wrote.contains(outcome):
          _logger.detail('Wrote $path');
        case _:
      }
    }
  }

  /// Warns about each file where the user's values were kept over VGV's.
  void _reportKept(List<AppliedChange> applied) {
    final kept = applied.where(
      (change) => _keptUserValues.contains(change.outcome),
    );
    for (final AppliedChange(:change) in kept) {
      _logger.warn('Kept your values in ${change.file.path}');
    }
    if (kept.isNotEmpty) {
      _logger.info("Pass ${lightCyan.wrap('--force')} to take VGV's.");
    }
  }

  /// Summarizes how many files were written per owner, or that nothing
  /// needed to be.
  void _reportWritten(List<AppliedChange> applied, {required bool dryRun}) {
    final written = applied
        .where((change) => _wrote.contains(change.outcome))
        .groupListsBy((change) => change.change.harness);

    if (written.isEmpty) {
      if (applied.every(
        (change) => change.outcome == ChangeOutcome.unchanged,
      )) {
        _logger.info('Everything is already up to date.');
      }
      return;
    }

    for (final MapEntry(key: harness, value: changes) in written.entries) {
      _logger.info('  ${_ownerName(harness)}: ${changes.length} file(s)');
    }

    _logger.info(
      dryRun
          ? '\n${lightYellow.wrap('--check')} so nothing was written.'
          : '\nRestart your coding agents to pick up the changes.',
    );
  }
}

/// How [harness] is named in the report, with the shared skills as `Shared`.
String _ownerName(Harness? harness) => harness?.displayName ?? 'Shared';
