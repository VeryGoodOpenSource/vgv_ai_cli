import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';

/// {@template plugin_resolution}
/// The outcome of asking one source for a plugin.
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
final class ResolvedPlugin extends PluginResolution {
  /// {@macro resolved_plugin}
  const new(this.directory);

  /// Where the plugin's contents live.
  final Directory directory;
}

/// {@template unavailable_plugin}
/// No source could supply the plugin, for [reasons].
/// {@endtemplate}
final class UnavailablePlugin extends PluginResolution {
  /// One reason per source that was tried, in the order they were tried.
  const new(this.reasons);

  /// {@macro unavailable_plugin}
  ///
  /// Convenience for a single source, which has exactly one reason.
  new single(String reason) : reasons = [reason];

  /// Why each source could not supply the plugin, phrased for a user.
  ///
  /// A list rather than a joined string, so a chain of sources can concatenate
  /// without the exception losing which source said what.
  final List<String> reasons;
}

/// {@template plugin_resolution_exception}
/// Thrown when every source failed to supply a plugin.
/// {@endtemplate}
class PluginResolutionException implements Exception {
  /// {@macro plugin_resolution_exception}
  const new(this.ref, this.reasons);

  /// The plugin that could not be resolved.
  final PluginRef ref;

  /// Each source's reason, in the order the sources were tried.
  final List<String> reasons;

  @override
  String toString() {
    final detail = reasons.map((reason) => '  - $reason').join('\n');
    return 'Could not resolve $ref:\n$detail';
  }
}

/// {@template plugin_parse_exception}
/// Thrown when a plugin file exists but cannot be understood.
///
/// Deliberately not a [FormatException]. `YamlException` and `jsonDecode` both
/// throw `FormatException`, which the command runner catches and renders as a
/// CLI usage error, so a corrupt plugin file would tell the user their
/// command-line arguments were wrong.
/// {@endtemplate}
class PluginParseException implements Exception {
  /// {@macro plugin_parse_exception}
  const new(this.path, this.message);

  /// The file that could not be parsed.
  final String path;

  /// What the parser objected to.
  final String message;

  @override
  String toString() => 'Could not parse $path: $message';
}

/// {@template missing_home_exception}
/// Thrown when neither `HOME` nor `USERPROFILE` is set.
/// {@endtemplate}
class MissingHomeException implements Exception {
  /// {@macro missing_home_exception}
  const new();

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
