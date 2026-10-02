import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/model/model.dart';

/// {@template plugin_resolver}
/// Resolves and parses the pinned VGV plugins into one asset bundle.
///
/// Each plugin comes from the Claude Code cache when it holds a complete copy,
/// and is otherwise cloned at its `gitRef` into `~/.vgv_ai/plugins`, where it
/// is kept for later runs. This is the one place both `install` and `doctor`
/// get their plugins from.
/// {@endtemplate}
class PluginResolver {
  /// {@macro plugin_resolver}
  const new({
    RunProcess? runProcess,
    this._parser = const ClaudePluginParser(),
    this._plugins = vgvPlugins,
  }) : _runProcess = runProcess ?? Process.run;

  final RunProcess _runProcess;
  final PluginParser _parser;
  final List<PluginRef> _plugins;

  /// Resolves every plugin for [home], stopping at the first that cannot be
  /// resolved or parsed: a half-configured harness is worse than an
  /// unconfigured one.
  Future<AssetResolution> resolve(Directory home) async {
    final source = ChainedPluginSource([
      LocalCachePluginSource(home: home),
      GitPluginSource(
        cacheRoot: home.childDirectory('.vgv_ai').childDirectory('plugins'),
        runGit: (args) => _runProcess('git', args),
      ),
    ]);

    final parsed = <PluginAssets>[];
    for (final plugin in _plugins) {
      switch (await source.resolve(plugin)) {
        case ResolvedPlugin(:final directory):
          try {
            parsed.add(_parser.parse(directory));
          } on PluginParseException catch (error) {
            return UnparseableAssets(plugin, error);
          }
        case UnavailablePlugin(:final reasons):
          return UnavailableAssets(plugin, reasons);
      }
    }

    return ResolvedAssets(
      assets: PluginAssets.merge(parsed),
      plugins: _plugins,
    );
  }
}
