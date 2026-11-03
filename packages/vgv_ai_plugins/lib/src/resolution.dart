import 'package:file/file.dart';

/// {@template plugin_resolution}
/// The outcome of asking a source for a plugin.
///
/// A nullable [Directory] would discard *why* a source could not supply the
/// plugin, collapsing a cache miss, a missing tag, an absent git binary and an
/// unwritable cache root into one indistinguishable `null`.
/// {@endtemplate}
sealed class const PluginResolution() {
  /// {@macro plugin_resolution}
  this;
}

/// {@template resolved_plugin}
/// The plugin was found on disk at [directory].
/// {@endtemplate}
final class const ResolvedPlugin(final Directory directory)
    extends PluginResolution {
  /// {@macro resolved_plugin}
  this;
}

/// {@template unavailable_plugin}
/// No source could supply the plugin.
///
/// [reasons] holds one entry per source that was tried, in the order they were
/// tried. A list rather than a joined string, so a chain of sources can
/// concatenate without losing which source said what.
/// {@endtemplate}
final class const UnavailablePlugin(final List<String> reasons)
    extends PluginResolution {
  /// {@macro unavailable_plugin}
  this;

  /// {@macro unavailable_plugin}
  ///
  /// Convenience for a single source, which has exactly one reason.
  new single(String reason) : this([reason]);
}
