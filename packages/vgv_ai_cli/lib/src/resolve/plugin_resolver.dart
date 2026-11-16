import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/model/model.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

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
  /// {@macro plugin_resolver}
  this;

  /// Resolves the plugins [only] names for [home], or every pinned one when
  /// it names none, stopping at the first that cannot be resolved or parsed:
  /// a half-configured harness is worse than an unconfigured one.
  ///
  /// [log] receives the git command line and its stderr, for `--verbose`.
  ///
  /// A skill or agent body names the plugin's files under what [pluginRoot]
  /// answers for it, such as `Scope.pluginRoot`, or under the directory the
  /// plugin was resolved to when it answers null.
  Future<AssetResolution> resolve(
    Directory home, {
    Set<String>? only,
    LogDetail? log,
    String? Function(PluginRef plugin)? pluginRoot,
  }) async {
    final sources = [
      LocalCachePluginSource(home: home),
      GitPluginSource(
        cacheRoot: home.childDirectory('.vgv_ai').childDirectory('plugins'),
        runGit: (args) => _runProcess('git', args),
        log: log,
      ),
    ];

    final plugins = [
      for (final plugin in _plugins)
        if (only?.contains(plugin.name) ?? true) plugin,
    ];

    final parsed = <PluginAssets>[];
    final directories = <PluginDirectory>[];
    for (final plugin in plugins) {
      final rootReference = pluginRoot?.call(plugin);
      switch (await _resolveOne(plugin, sources, rootReference)) {
        case ResolvedAssets(:final assets, directories: final resolved):
          parsed.add(assets);
          directories.addAll(resolved);
        case final UnavailableAssets failure:
          return failure;
        case final UnparseableAssets failure:
          return failure;
      }
    }

    return ResolvedAssets(
      assets: PluginAssets.merge(parsed, plugins: plugins),
      directories: directories,
    );
  }

  /// [plugin] parsed from the first of [sources] holding a copy that parses,
  /// naming its files under [rootReference] when there is one.
  ///
  /// A copy that fails to parse falls through to the next source rather than
  /// failing the run: Claude Code fills its cache from the plugin's default
  /// branch, not the pinned tag, so the cache can hold content the pin never
  /// vetted. When no copy parses, the last parse error is reported, since a
  /// copy that exists says more than a source that has none.
  Future<AssetResolution> _resolveOne(
    PluginRef plugin,
    List<PluginSource> sources,
    String? rootReference,
  ) async {
    final reasons = <String>[];
    UnparseableAssets? unparseable;
    for (final source in sources) {
      switch (await source.resolve(plugin)) {
        case ResolvedPlugin(:final directory):
          try {
            return ResolvedAssets(
              assets: _parser.parse(directory, rootReference: rootReference),
              directories: [
                PluginDirectory(plugin: plugin, directory: directory),
              ],
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
