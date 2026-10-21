import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/model/model.dart';

/// {@template plugin_resolver}
/// Resolves and parses the pinned VGV plugins into one asset bundle.
///
/// Each plugin comes from the Claude Code cache when it holds a complete copy
/// that parses, and is otherwise cloned at its `gitRef` into
/// `~/.vgv_ai/plugins`, where it is kept for later runs. This is the one place
/// both `install` and `doctor` get their plugins from.
/// {@endtemplate}
class const PluginResolver({
  final RunProcess _runProcess = Process.run,
  final PluginParser _parser = const ClaudePluginParser(),
  final List<PluginRef> _plugins = vgvPlugins,
}) {
  /// Resolves the plugins [only] names for [home], or every pinned one when
  /// it names none, stopping at the first that cannot be resolved or parsed:
  /// a half-configured harness is worse than an unconfigured one.
  Future<AssetResolution> resolve(Directory home, {Set<String>? only}) async {
    final sources = [
      LocalCachePluginSource(home: home),
      GitPluginSource(
        cacheRoot: home.childDirectory('.vgv_ai').childDirectory('plugins'),
        runGit: (args) => _runProcess('git', args),
      ),
    ];

    final plugins = [
      for (final plugin in _plugins)
        if (only?.contains(plugin.name) ?? true) plugin,
    ];

    final parsed = <PluginAssets>[];
    for (final plugin in plugins) {
      switch (await _resolveOne(plugin, sources)) {
        case ResolvedAssets(:final assets):
          parsed.add(assets);
        case final UnavailableAssets failure:
          return failure;
        case final UnparseableAssets failure:
          return failure;
      }
    }

    return ResolvedAssets(assets: PluginAssets.merge(parsed));
  }

  /// [plugin] parsed from the first of [sources] holding a copy that parses.
  ///
  /// A copy that fails to parse falls through to the next source rather than
  /// failing the run: Claude Code fills its cache from the plugin's default
  /// branch, not the pinned tag, so the cache can hold content the pin never
  /// vetted. When no copy parses, the last parse error is reported, since a
  /// copy that exists says more than a source that has none.
  Future<AssetResolution> _resolveOne(
    PluginRef plugin,
    List<PluginSource> sources,
  ) async {
    final reasons = <String>[];
    UnparseableAssets? unparseable;
    for (final source in sources) {
      switch (await source.resolve(plugin)) {
        case ResolvedPlugin(:final directory):
          try {
            return ResolvedAssets(
              assets: _parser.parse(directory).withPlugin(plugin),
            );
          } on PluginParseException catch (error) {
            unparseable = UnparseableAssets(plugin, error);
          }
        case UnavailablePlugin(reasons: final unavailable):
          reasons.addAll(unavailable);
      }
    }
    return unparseable ?? UnavailableAssets(plugin, reasons);
  }
}
