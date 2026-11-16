import 'dart:io' show stdin;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/commands/reporting_manifest_store.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template install_command}
/// Configures the Very Good AI tooling for the detected coding-agent harnesses.
///
/// * `--check` prints the changes without writing them. It still asks which
///   plugins to install in a terminal, so it shows what a real run would do.
/// * `--force` takes VGV's values where they conflict with the user's.
/// * `--only` configures the named harnesses, detected or not.
/// * `--no-<harness>` skips one detected harness. It cannot be combined with
///   `--only`, which already names the set.
/// * `--plugin` installs just the named VGV plugins. Without it, a run in a
///   terminal asks which plugins to install, and any other run installs
///   every pinned one.
/// * `--refresh` reinstalls the harnesses and plugins the manifest records,
///   at the pinned versions, without asking. `update` runs it.
/// {@endtemplate}
class InstallCommand({
  required final Logger _logger,
  final Directory? _home,
  final Map<String, String>? _environment,
  final PluginResolver _resolver = const PluginResolver(),
  final HarnessDetector _detector = const HarnessDetector(),
  final Translator _translator = const Translator(),
  final Reconciler _reconciler = const Reconciler(),
  bool? hasTerminal,
}) extends Command<int> with HarnessSelection {
  /// {@macro install_command}
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
        help: 'Install just these VGV plugins instead of choosing them.',
        allowed: [for (final plugin in vgvPlugins) plugin.name],
      )
      ..addFlag(
        refreshFlag,
        help:
            'Reinstall the harnesses and plugins a previous install wrote, '
            'at the pinned versions.',
        negatable: false,
        hide: true,
      );
    addHarnessOptions('Configure the Very Good AI tooling for');
  }

  /// The name the CLI registers `install` under, so other code can name it
  /// without constructing one.
  static const String commandName = 'install';

  /// The flag `update` passes to reinstall what a previous install wrote.
  /// Older versions of `update` pass it too, so it must keep its name.
  static const String refreshFlag = 'refresh';

  /// Whether stdin is a terminal, so install can ask which plugins to install.
  final bool _hasTerminal = hasTerminal ?? stdin.hasTerminal;

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
  Directory? get home => commandHome(_home, _environment);

  @override
  Future<int> run() async {
    final force = argResults!['force'] == true;
    final dryRun = argResults!['check'] == true;
    final refresh = argResults![refreshFlag] == true;
    if (refresh) _rejectSelectionWithRefresh();

    // Falling back to the working directory would scatter harness config
    // wherever install happened to run, so a missing home is fatal.
    final home = this.home;
    if (home == null) {
      _logger.err(
        'Could not find your home directory. Set HOME and run install again.',
      );
      return ExitCode.config.code;
    }

    // Loaded before anything is resolved, since a manifest this version
    // cannot read means nothing can be installed.
    final store = ReportingManifestStore(
      ManifestStore(home),
      _logger,
      nothingDone: 'Installed nothing',
      done: 'written',
      retry: 'install',
    );
    final manifest = store.load();
    if (manifest == null) return ExitCode.ioError.code;

    final selected = refresh ? manifest.plugins.keys.toSet() : await _select();
    if (selected.isEmpty) {
      _logger.err(refresh ? _nothingToRefresh : _noHarnessSelected);
      return ExitCode.usage.code;
    }

    final plugins = refresh
        ? _recordedPlugins(manifest, selected)
        : _selectPlugins(manifest, selected);
    if (plugins.isEmpty) {
      _logger.err(
        'No plugin selected. Choose at least one, or pass --plugin to name '
        'one explicitly.',
      );
      return ExitCode.usage.code;
    }

    final resolved = await _resolveAssets(home, plugins);
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
            _pluginVersions(manifest, resolved.assets.plugins, selected),
          ),
        );
    final anyChangeFailed = applied.any(
      (change) => change.outcome == ChangeOutcome.failed,
    );
    return !recorded || anyChangeFailed
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// Why there is nothing to install when no harness is selected.
  static final String _noHarnessSelected =
      'No harness selected. Install one of '
      '${Harness.values.map((harness) => harness.displayName).join(', ')}, '
      'or pass --only to name one explicitly.';

  /// Why `--refresh` installs nothing when the manifest records no plugins.
  static const String _nothingToRefresh =
      'Nothing to refresh: no previous install recorded its plugins. Run '
      'install to choose them.';

  /// Throws a [UsageException] when `--refresh` is combined with an option
  /// that picks harnesses or plugins, since it takes both from the manifest.
  void _rejectSelectionWithRefresh() {
    final picked = [
      'only',
      'plugin',
      ...Harness.values.map((harness) => harness.name),
    ].where(argResults!.wasParsed);
    if (picked.isNotEmpty) {
      usageException(
        '--$refreshFlag cannot be combined with '
        '${picked.map((option) => '--$option').join(', ')}.',
      );
    }
  }

  /// The plugins [manifest] records for [selected] that this version still
  /// pins, warning about the ones it no longer does.
  Set<String> _recordedPlugins(
    InstallManifest manifest,
    Set<Harness> selected,
  ) {
    final recorded = {
      for (final harness in selected) ...?manifest.plugins[harness]?.keys,
    };
    final pinned = {for (final plugin in vgvPlugins) plugin.name};
    final dropped = recorded.difference(pinned);
    if (dropped.isNotEmpty) {
      _logger.warn(
        'Skipping ${dropped.join(', ')}, which this version no longer '
        'installs.',
      );
    }
    return recorded.intersection(pinned);
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

  /// The plugins to install for [selected]: the ones `--plugin` names, or
  /// when it names none, the ones the user picks in a terminal, or every
  /// pinned plugin outside one.
  ///
  /// The picker starts from the pinned plugins [manifest] records for
  /// [selected], so a rerun keeps what the user chose before, and from every
  /// pinned plugin when it records none of them. A recorded plugin the user
  /// leaves out stays installed, which the user is told, since a picker
  /// suggests otherwise.
  Set<String> _selectPlugins(InstallManifest manifest, Set<Harness> selected) {
    final names = argResults!['plugin'] as List<String>;
    if (names.isNotEmpty) return names.toSet();
    if (!_hasTerminal) {
      return {for (final plugin in vgvPlugins) plugin.name};
    }

    final recorded = {
      for (final harness in selected) ...?manifest.plugins[harness]?.keys,
    };
    final installed = [
      for (final plugin in vgvPlugins)
        if (recorded.contains(plugin.name)) plugin,
    ];
    final chosen = _logger.chooseAny(
      'Which VGV plugins should be installed?',
      choices: vgvPlugins,
      defaultValues: installed.isEmpty ? vgvPlugins : installed,
      display: (plugin) => plugin.name,
    );
    final picked = {for (final plugin in chosen) plugin.name};

    final kept = recorded.difference(picked);
    if (picked.isNotEmpty && kept.isNotEmpty) {
      _logger.info(
        'Keeping ${kept.join(', ')}, which a previous install wrote. Run '
        "${lightCyan.wrap('uninstall')} to remove VGV's plugins.",
      );
    }
    return picked;
  }

  /// The versions to record for each harness of [selected]: [installed] for
  /// the plugins this run wrote, and what [manifest] already records for the
  /// ones it skipped, whose files are still installed. Every other harness
  /// keeps what it had.
  Map<Harness, Map<String, String>> _pluginVersions(
    InstallManifest manifest,
    List<PluginRef> installed,
    Set<Harness> selected,
  ) {
    final written = {
      for (final plugin in installed) plugin.name: plugin.version,
    };
    return {
      ...manifest.plugins,
      for (final harness in selected)
        harness: {
          for (final plugin in vgvPlugins)
            plugin.name:
                ?(written[plugin.name] ??
                manifest.plugins[harness]?[plugin.name]),
        },
    };
  }

  /// Resolves and parses the [plugins] into one asset bundle.
  ///
  /// Returns `null`, having said why, when any plugin cannot be resolved or
  /// parsed.
  Future<ResolvedAssets?> _resolveAssets(
    Directory home,
    Set<String> plugins,
  ) async {
    final progress = _logger.progress('Resolving plugins');

    switch (await _resolver.resolve(home, only: plugins, log: _logger.detail)) {
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
