/// {@template plugin_exception}
/// Base type for every failure raised while reading a Claude plugin.
///
/// Sealed so a caller can switch exhaustively when mapping a failure onto an
/// exit code. Implements [Exception] rather than extending [Error] because
/// `very_good_analysis` enables `only_throw_errors`.
/// {@endtemplate}
sealed class PluginException implements Exception {
  /// {@macro plugin_exception}
  const new(this.path, this.message);

  /// The filesystem path the failure relates to.
  final String path;

  /// A human readable explanation of what went wrong.
  final String message;

  /// A short, stable name for this kind of failure.
  ///
  /// Declared per subclass rather than read from `runtimeType`, which
  /// `very_good_analysis` forbids in production code.
  String get kind;

  @override
  String toString() => '$kind: $path: $message';
}

/// {@template missing_plugin_metadata}
/// A plugin directory has no `.claude-plugin/plugin.json`.
/// {@endtemplate}
final class MissingPluginMetadata extends PluginException {
  /// {@macro missing_plugin_metadata}
  const new(String path) : super(path, 'no .claude-plugin/plugin.json found');

  @override
  String get kind => 'MissingPluginMetadata';
}

/// {@template invalid_plugin_metadata}
/// A `.claude-plugin/plugin.json` exists but cannot be used.
/// {@endtemplate}
final class InvalidPluginMetadata extends PluginException {
  /// {@macro invalid_plugin_metadata}
  const new(super.path, super.message);

  @override
  String get kind => 'InvalidPluginMetadata';
}

/// {@template no_agents_found}
/// A plugin has no `agents/` directory, or it contains no agent files.
///
/// Fatal rather than an empty result: an empty manifest generates nothing, and
/// the user would otherwise see a clean exit with no output and no reason.
/// {@endtemplate}
final class NoAgentsFound extends PluginException {
  /// {@macro no_agents_found}
  const new(String path) : super(path, 'no agents found under agents/');

  @override
  String get kind => 'NoAgentsFound';
}

/// {@template invalid_agent}
/// An agent file exists but its frontmatter cannot be used.
/// {@endtemplate}
final class InvalidAgent extends PluginException {
  /// {@macro invalid_agent}
  const new(super.path, super.message);

  @override
  String get kind => 'InvalidAgent';
}

/// {@template duplicate_agent_id}
/// Two agent files in one plugin resolve to the same id.
///
/// Fatal rather than last-write-wins: a target such as Codex writes agents into
/// a flat directory, so the generator derives a filename from the id and cannot
/// resolve a collision that already happened upstream.
/// {@endtemplate}
final class DuplicateAgentId extends PluginException {
  /// {@macro duplicate_agent_id}
  const new(super.path, super.message);

  @override
  String get kind => 'DuplicateAgentId';
}

/// {@template unreadable_file}
/// A file could not be read, for example because of its encoding or
/// permissions.
/// {@endtemplate}
final class UnreadableFile extends PluginException {
  /// {@macro unreadable_file}
  const new(super.path, super.message);

  @override
  String get kind => 'UnreadableFile';
}
