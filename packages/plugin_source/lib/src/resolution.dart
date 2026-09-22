import 'package:file/file.dart';
import 'package:plugin_source/src/plugin_ref.dart';

/// {@template plugin_resolution}
/// The outcome of asking a source for a plugin.
///
/// A nullable [Directory] would discard *why* a source could not supply the
/// plugin, collapsing a cache miss, a missing tag, an absent git binary and an
/// unwritable cache root into one indistinguishable `null`.
/// {@endtemplate}
sealed class PluginResolution {
  /// {@macro plugin_resolution}
  const new();
}

/// {@template resolved_plugin}
/// The plugin was found on disk at [directory].
/// {@endtemplate}
final class const ResolvedPlugin(final Directory directory)
    extends PluginResolution;

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
  ///
  /// Convenience for a single source, which has exactly one reason.
  new single(String reason) : this([reason]);
}

/// {@template plugin_resolution_exception}
/// Thrown when every source failed to supply [ref].
/// {@endtemplate}
class const PluginResolutionException(
  final PluginRef ref,
  final List<String> reasons,
) implements Exception {
  @override
  String toString() {
    final detail = reasons.map((reason) => '  - $reason').join('\n');
    return 'Could not resolve $ref:\n$detail';
  }
}

/// {@template missing_home_exception}
/// Thrown when neither `HOME` nor `USERPROFILE` is set.
/// {@endtemplate}
class const MissingHomeException() implements Exception {
  @override
  String toString() =>
      'Could not determine your home directory: neither HOME nor USERPROFILE '
      'is set.';
}

/// Resolves the user's home directory.
///
/// [environment] and [isWindows] are parameters rather than reads of
/// `Platform`, because CI runs Linux only and a `Platform.isWindows` branch
/// could never execute there.
Directory resolveHome({
  required FileSystem fileSystem,
  required Map<String, String> environment,
  required bool isWindows,
}) {
  final candidates = isWindows
      ? const ['USERPROFILE', 'HOME']
      : const ['HOME', 'USERPROFILE'];

  for (final key in candidates) {
    final value = environment[key];
    if (value != null && value.isNotEmpty) return fileSystem.directory(value);
  }

  throw const MissingHomeException();
}
