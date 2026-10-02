import 'package:plugin_source/plugin_source.dart';

/// {@template asset_resolution}
/// What resolving and parsing every pinned plugin produced.
/// {@endtemplate}
sealed class AssetResolution {
  /// {@macro asset_resolution}
  const new();
}

/// {@template resolved_assets}
/// Every plugin in [plugins] resolved and parsed, merged into [assets].
/// {@endtemplate}
final class const ResolvedAssets({
  /// What the plugins contribute, merged.
  required final PluginAssets assets,

  /// The plugins that were resolved, at the versions they were pinned to.
  required final List<PluginRef> plugins,
}) extends AssetResolution;

/// {@template unavailable_assets}
/// No source could supply [plugin], for each of [reasons].
/// {@endtemplate}
final class const UnavailableAssets(
  /// The first plugin that could not be resolved.
  final PluginRef plugin,

  /// Why, one reason per source tried, in the order they were tried.
  final List<String> reasons,
) extends AssetResolution;

/// {@template unparseable_assets}
/// [plugin] resolved, but could not be parsed because of [error].
/// {@endtemplate}
final class const UnparseableAssets(
  /// The plugin that could not be parsed.
  final PluginRef plugin,

  /// Why it could not be parsed.
  final PluginParseException error,
) extends AssetResolution;
