import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/document/file_system.dart';
import 'package:vgv_ai_cli/src/harness/harness_detector.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';
import 'package:vgv_ai_cli/src/manifest/manifest_store.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';

/// {@template install_command}
/// Configures Very Good AI tooling across the detected coding-agent harnesses.
///
/// * `--check` prints the changes without writing them.
/// * `--force` takes VGV's values where they conflict with the user's.
/// * `--only` configures the named harnesses, detected or not.
/// * `--no-<harness>` skips one detected harness. It cannot be combined with
///   `--only`, which already names the set.
/// {@endtemplate}
class InstallCommand extends Command<int> {
  /// {@macro install_command}
  new({
    required this._logger,
    this._home,
    this._environment,
    this._pluginSource,
    this._parser = const ClaudePluginParser(),
    this._detector = const HarnessDetector(),
    this._translator = const Translator(),
    this._reconciler = const Reconciler(),
  }) {
    argParser
      ..addFlag(
        'check',
        help: 'Print what would change without writing anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help:
            'Overwrite your values when they conflict with the ones install '
            'writes.',
        negatable: false,
      )
      ..addMultiOption(
        'only',
        help:
            'Configure just these harnesses, whether or not they are '
            'detected.',
        allowed: Harness.values.map((harness) => harness.name),
      );

    // Opting out matters more than opting in: the default is every harness that
    // is actually installed, so `--no-<harness>` is how the set is narrowed.
    for (final harness in Harness.values) {
      argParser.addFlag(
        harness.name,
        defaultsTo: true,
        help: 'Configure ${harness.displayName}.',
      );
    }
  }

  final Logger _logger;
  final Directory? _home;
  final Map<String, String>? _environment;
  final PluginSource? _pluginSource;
  final PluginParser _parser;
  final HarnessDetector _detector;
  final Translator _translator;
  final Reconciler _reconciler;

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
      'Configure Very Good AI tooling for your coding agents.';

  @override
  String get name => commandName;

  /// The home directory [environment] names, or null when it names none.
  static Directory? userHome(Map<String, String> environment) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    return home == null ? null : const LocalFileSystem().directory(home);
  }

  /// The directory install configures, or null when it cannot be found.
  Directory? get home =>
      _home ?? userHome(_environment ?? Platform.environment);

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
    final store = ManifestStore(home);
    final manifest = _load(store);
    if (manifest == null) return ExitCode.ioError.code;

    final assets = await _resolveAssets(
      _pluginSource ?? LocalCachePluginSource(home: home),
    );
    if (assets == null) return ExitCode.unavailable.code;

    final plan = await _translator.translate(
      assets: assets,
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
        dryRun || _record(store, from: manifest, to: reconciliation.manifest);
    return !recorded ||
            applied.any((change) => change.outcome == ChangeOutcome.failed)
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// The manifest in [store], or null, having said why, when it cannot be
  /// read or was written by another version.
  InstallManifest? _load(ManifestStore store) {
    try {
      final manifest = store.load();
      if (manifest == null) {
        _logger.err(
          'Installed nothing, because ${ManifestStore.unreadable}: '
          '${store.file.path}',
        );
      }
      return manifest;
    } on FileSystemException catch (error) {
      _logger.err(
        'Installed nothing, because ${store.file.path} could not be read: '
        '${error.description}',
      );
      return null;
    }
  }

  /// Saves [to] in [store] unless it records nothing [from] does not, and
  /// returns whether it could.
  ///
  /// A manifest that could not be saved still holds its old entries, so the
  /// files this run wrote count as the user's until a later run records
  /// them.
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
        'Could not record what was written in ${store.file.path}: '
        '${error.description}',
      );
      return false;
    }
  }

  /// Resolves which harnesses to configure.
  ///
  /// `--only` wins outright and bypasses detection. Otherwise every harness
  /// that is both enabled and actually installed is configured, since writing
  /// config for a harness the user does not have is noise. Only enabled
  /// harnesses are probed, since each probe may wait out a timeout.
  Future<Set<Harness>> _select() async {
    final results = argResults!;
    final only = results['only'] as List<String>;
    if (only.isNotEmpty) {
      final flagged = Harness.values.where((h) => results.wasParsed(h.name));
      if (flagged.isNotEmpty) {
        usageException(
          '--only cannot be combined with '
          '${flagged.map((harness) => '--[no-]${harness.name}').join(', ')}.',
        );
      }
      return only.map(Harness.values.byName).toSet();
    }

    final enabled = <Harness>[];
    for (final harness in Harness.values) {
      if (results[harness.name] == true) {
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

  /// Resolves and parses every pinned VGV plugin into one asset bundle.
  ///
  /// Returns `null` when any plugin cannot be resolved: a half-configured
  /// harness is worse than an unconfigured one, so the first failure aborts.
  Future<PluginAssets?> _resolveAssets(PluginSource pluginSource) async {
    final progress = _logger.progress('Resolving plugins');
    final parsed = <PluginAssets>[];

    for (final ref in vgvPlugins) {
      final resolution = await pluginSource.resolve(ref);

      switch (resolution) {
        case ResolvedPlugin(:final directory):
          try {
            parsed.add(_parser.parse(directory));
          } on PluginParseException catch (error) {
            progress.fail('Could not parse $ref');
            _logger.err('  - $error');
            return null;
          }
        case UnavailablePlugin(:final reasons):
          progress.fail('Could not resolve $ref');
          for (final reason in reasons) {
            _logger.err('  - $reason');
          }
          _logger.err(
            'Install Claude Code and its VGV plugins so they are cached, then '
            'run install again.',
          );
          return null;
      }
    }

    final assets = PluginAssets.merge(parsed);
    progress.complete(
      'Resolved ${assets.skills.length} skills and '
      '${assets.agents.length} agents',
    );
    return assets;
  }

  /// Prints what could not be translated, the files that could not be
  /// written or kept the user's values, and then what was written per owner.
  void _report(
    TranslationPlan plan,
    List<AppliedChange> applied, {
    required bool dryRun,
  }) {
    String ownerName(Harness? harness) => harness?.displayName ?? 'Shared';

    for (final note in plan.shared?.notes ?? const <TranslationNote>[]) {
      _logger.warn('${ownerName(null)}: $note');
    }
    for (final MapEntry(key: harness, value: result)
        in plan.harnesses.entries) {
      for (final note in result.notes) {
        _logger.warn('${ownerName(harness)}: $note');
      }
    }

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

    final kept = applied.where(
      (change) => _keptUserValues.contains(change.outcome),
    );
    for (final AppliedChange(:change) in kept) {
      _logger.warn('Kept your values in ${change.file.path}');
    }
    if (kept.isNotEmpty) {
      _logger.info("Pass ${lightCyan.wrap('--force')} to take VGV's.");
    }

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
      _logger.info('  ${ownerName(harness)}: ${changes.length} file(s)');
    }

    _logger.info(
      dryRun
          ? '\n${lightYellow.wrap('--check')} so nothing was written.'
          : '\nRestart your coding agents to pick up the changes.',
    );
  }
}
