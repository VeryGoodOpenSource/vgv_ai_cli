import 'dart:io' show Platform;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/harness_detector.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/applied_change.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

/// {@template install_command}
/// Configures Very Good AI tooling across the detected coding-agent harnesses.
///
/// * `--check` prints the changes without writing them.
/// * `--force` takes VGV's values where they conflict with the user's.
/// * `--only` configures the named harnesses, detected or not.
/// * `--no-<harness>` skips one detected harness.
/// {@endtemplate}
class InstallCommand extends Command<int> {
  /// {@macro install_command}
  new({
    required this._logger,
    this._home,
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

  /// The current user's home directory.
  static Directory get userHome {
    final environment = Platform.environment;
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    return const LocalFileSystem().directory(home ?? '.');
  }

  Directory get home => _home ?? userHome;

  PluginSource get pluginSource =>
      _pluginSource ?? LocalCachePluginSource(home: home);

  @override
  Future<int> run() async {
    final force = argResults!['force'] == true;
    final dryRun = argResults!['check'] == true;

    final selected = await _select();
    if (selected.isEmpty) {
      _logger.err(
        'No harness selected. Install one of '
        '${Harness.values.map((harness) => harness.displayName).join(', ')}, '
        'or pass --only to name one explicitly.',
      );
      return ExitCode.usage.code;
    }

    final assets = await _resolveAssets();
    if (assets == null) return ExitCode.unavailable.code;

    final results = await _translator.translate(
      assets: assets,
      home: home,
      selected: selected,
    );

    final applied = _reconciler.apply(
      [for (final result in results.values) ...result.changes],
      manifest: installManifest(home),
      force: force,
      dryRun: dryRun,
    );

    _report(results, applied, dryRun: dryRun);
    return applied.any((change) => change.outcome == ChangeOutcome.failed)
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// Resolves which harnesses to configure.
  ///
  /// `--only` wins outright and bypasses detection. Otherwise every harness
  /// that is both enabled and actually installed is configured, since writing
  /// config for a harness the user does not have is noise.
  Future<Set<Harness>> _select() async {
    final only = argResults!['only'] as List<String>;
    if (only.isNotEmpty) return only.map(Harness.values.byName).toSet();

    final detections = await _detector.detectAll();
    final selected = <Harness>{};

    for (final harness in Harness.values) {
      if (argResults![harness.name] != true) {
        _logger.detail('Skipping ${harness.displayName}: opted out');
        continue;
      }

      if (detections[harness]?.installed != true) {
        _logger.info(
          '${lightYellow.wrap('skipped')} ${harness.displayName} '
          '(not installed)',
        );
        continue;
      }

      selected.add(harness);
    }

    return selected;
  }

  /// Resolves and parses every pinned VGV plugin into one asset bundle.
  ///
  /// Returns `null` when any plugin cannot be resolved: a half-configured
  /// harness is worse than an unconfigured one, so the first failure aborts.
  Future<PluginAssets?> _resolveAssets() async {
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
    Map<Harness?, TranslationResult> results,
    List<AppliedChange> applied, {
    required bool dryRun,
  }) {
    String ownerName(Harness? harness) => harness?.displayName ?? 'Shared';

    for (final MapEntry(key: harness, value: result) in results.entries) {
      for (final note in result.notes) {
        _logger.warn('${ownerName(harness)}: $note');
      }
    }

    for (final AppliedChange(:change, :outcome, :error) in applied) {
      final path = change.file.path;
      switch (outcome) {
        case ChangeOutcome.failed:
          _logger.err('Could not write $path: $error');
        case ChangeOutcome.unparseable:
          _logger.warn(
            'Left $path alone because it could not be parsed. If it has '
            "comments, add VGV's settings to it by hand.",
          );
        case _ when _wrote.contains(outcome):
          _logger.detail('${dryRun ? 'Would write' : 'Wrote'} $path');
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
      _logger.info('Everything is already up to date.');
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
