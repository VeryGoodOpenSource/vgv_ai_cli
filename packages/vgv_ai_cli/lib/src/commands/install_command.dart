import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/harness/harnesses.dart';
import 'package:vgv_ai_cli/src/harness/skills_writer.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';
import 'package:vgv_ai_cli/src/templates/templates.dart';

/// Builds a [MasonGenerator] from a bundle.
typedef GeneratorBuilder = Future<MasonGenerator> Function(MasonBundle);

/// {@template install_command}
/// `vgv_ai install`
///
/// Configures VGV agent tooling for every installed harness.
/// {@endtemplate}
class InstallCommand extends Command<int> {
  /// {@macro install_command}
  new({
    required this._logger,
    Directory? home,
    PluginSource? pluginSource,
    PluginAssetsReader? assetsReader,
    this._buildGenerator = MasonGenerator.fromBundle,
  }) : _home = home ?? _defaultHome(),
       _assetsReader = assetsReader ?? PluginAssetsReader(),
       _explicitSource = pluginSource {
    argParser
      ..addFlag(
        'check',
        help: 'Print what would change without writing anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help: 'Let VGV values win when they conflict with your own.',
        negatable: false,
      )
      ..addMultiOption(
        'only',
        help: 'Configure just these harnesses.',
        allowed: allHarnesses.map((h) => h.name),
      );

    // Opting out matters more than opting in: the default is everything that
    // is actually installed, so `--no-<harness>` is how you narrow it.
    for (final harness in allHarnesses) {
      argParser.addFlag(
        harness.name,
        defaultsTo: true,
        help: 'Configure ${harness.displayName}.',
      );
    }
  }

  static Directory _defaultHome() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return Directory(home ?? '.');
  }

  final Logger _logger;
  final Directory _home;
  final PluginAssetsReader _assetsReader;
  final GeneratorBuilder _buildGenerator;
  final PluginSource? _explicitSource;

  @override
  String get description =>
      'Configure VGV agent tooling for your installed coding agents.';

  @override
  String get name => 'install';

  PluginSource get _pluginSource {
    return _explicitSource ??
        ChainedPluginSource([
          LocalCachePluginSource(home: _home),
          GitPluginSource(
            cacheRoot: Directory(p.join(_home.path, '.vgv_ai', 'plugins')),
          ),
        ]);
  }

  @override
  Future<int> run() async {
    final dryRun = argResults?['check'] == true;
    final force = argResults?['force'] == true;

    final selected = await _select();
    if (selected.isEmpty) {
      _logger.err(
        'No harness selected. Install one of '
        '${allHarnesses.map((h) => h.displayName).join(', ')}, '
        'or pass --only to name one explicitly.',
      );
      return ExitCode.usage.code;
    }

    final assets = await _resolveAssets();
    if (assets == null) return ExitCode.unavailable.code;

    final staged = await _render(selected, assets);
    final changes = <PlannedChange>[
      // The canonical skills are shared, so they are planned once. Claude Code
      // gets them from the marketplace instead.
      if (selected.any((h) => h.name != 'claude'))
        ...const SkillsWriter().plan(assets: assets, home: _home),
      for (final harness in selected)
        ...harness.plan(assets: assets, home: _home, staged: staged),
    ];

    final applied = Reconciler(
      logger: _logger,
      force: force,
      dryRun: dryRun,
    ).apply(changes);

    _report(applied, dryRun: dryRun);
    return ExitCode.success.code;
  }

  /// Resolves which harnesses to configure.
  ///
  /// `--only` wins outright. Otherwise every harness that is both enabled and
  /// actually installed is configured, since writing config for a harness the
  /// user does not have is noise.
  Future<List<Harness>> _select() async {
    final only = argResults?['only'] as List<String>? ?? const [];
    if (only.isNotEmpty) {
      return allHarnesses.where((h) => only.contains(h.name)).toList();
    }

    final selected = <Harness>[];
    for (final harness in allHarnesses) {
      if (argResults?[harness.name] != true) {
        _logger.detail('Skipping ${harness.displayName}: opted out');
        continue;
      }
      if (!await harness.detected(logger: _logger)) {
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

  Future<PluginAssets?> _resolveAssets() async {
    final progress = _logger.progress('Resolving plugins');
    var assets = PluginAssets.empty;
    for (final ref in vgvPlugins) {
      final directory = await _pluginSource.resolve(ref, logger: _logger);
      if (directory == null) {
        progress.fail('Could not resolve $ref');
        _logger.err(
          'Install Claude Code and its VGV plugins, or check your network '
          'so the plugins can be cloned.',
        );
        return null;
      }
      assets = assets.merge(_assetsReader.read(directory));
    }
    progress.complete(
      'Resolved ${assets.skills.length} skills and '
      '${assets.agents.length} agents',
    );
    return assets;
  }

  /// Renders the brick into memory.
  ///
  /// The brick never generates into `$HOME`. Its output is staged in a temp
  /// directory, read back, and handed to the harnesses so the reconciler can
  /// decide how each file reaches its destination.
  Future<StagedOutput> _render(
    List<Harness> selected,
    PluginAssets assets,
  ) async {
    final generator = await _buildGenerator(vgvAgentsBundle);
    final staging = Directory.systemTemp.createTempSync('vgv_ai_staging_');

    try {
      var vars = <String, dynamic>{
        for (final harness in allHarnesses)
          harness.name: selected.any((h) => h.name == harness.name),
        'marketplace': vgvMarketplace,
        'skills_root': agentsSkillsRoot(_home),
        'skills': [
          for (final skill in assets.skills)
            {'name': skill.name, 'description': skill.description},
        ],
        'agents': [
          for (final agent in assets.agents)
            {'name': agent.name, 'description': agent.description},
        ],
        'mcp_servers': assets.mcpServers,
      };

      await generator.hooks.preGen(
        vars: vars,
        onVarsChanged: (updated) => vars = updated,
      );
      await generator.generate(
        DirectoryGeneratorTarget(staging),
        vars: vars,
        fileConflictResolution: FileConflictResolution.overwrite,
      );

      return {
        for (final file in staging.listSync().whereType<File>())
          p.basename(file.path): file.readAsStringSync(),
      };
    } finally {
      staging.deleteSync(recursive: true);
    }
  }

  void _report(List<AppliedChange> applied, {required bool dryRun}) {
    final written = applied
        .where((a) => a.outcome != ChangeOutcome.unchanged)
        .length;
    final byHarness = <String, int>{};
    for (final change in applied) {
      if (change.outcome == ChangeOutcome.unchanged) continue;
      byHarness.update(change.change.harness, (v) => v + 1, ifAbsent: () => 1);
    }

    if (written == 0) {
      _logger.info('Everything is already up to date.');
      return;
    }

    for (final MapEntry(:key, :value) in byHarness.entries) {
      _logger.info('  $key: $value file(s)');
    }
    _logger.info(
      dryRun
          ? '\n${lightYellow.wrap('--check')} so nothing was written.'
          : '\nRun ${lightCyan.wrap('vgv_ai doctor')} to verify.',
    );
  }
}
