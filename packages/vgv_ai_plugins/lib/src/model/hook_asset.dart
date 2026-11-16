import 'package:file/file.dart';

/// {@template hook_command}
/// One command a hook runs when its event fires.
///
/// [type] is the handler type as the source harness names it, such as
/// `command`. [timeout] is in seconds, or null for the harness default.
/// [command] is a shell command. Where it references the plugin's own files it
/// uses the [rootPlaceholder], which no harness understands natively;
/// substituting the real location is a translator's job.
///
/// Skill and agent bodies differ: parsers resolve the placeholder there to the
/// plugin's path themselves, since a body is prose read in place rather than a
/// command a translator rewrites.
/// {@endtemplate}
class const HookCommand({
  /// The handler type as the source harness names it, such as `command`.
  required final String type,

  /// The shell command, naming the plugin's files through [rootPlaceholder].
  required final String command,

  /// The timeout in seconds, or null for the harness default.
  final int? timeout,
}) {
  /// {@macro hook_command}
  this;

  /// Stands in for the plugin's root directory inside [command].
  ///
  /// Parsers rewrite their harness's own placeholder to this one, so
  /// translators substitute exactly one token regardless of where a plugin
  /// came from.
  static const rootPlaceholder = r'${PLUGIN_ROOT}';
}

/// {@template hook_asset}
/// One hook registration resolved from a plugin.
///
/// [event] is the lifecycle point, carried as the source harness names it.
/// [matcher] narrows which tools it fires for. [plugin] and [pluginRoot] are
/// the plugin's name, as its manifest declares it, and the directory
/// [HookCommand.rootPlaceholder] stands for. [agent] is the agent that
/// declared the hook for itself, or null.
/// {@endtemplate}
class const HookAsset({
  /// The lifecycle point, as the source harness names it.
  required final String event,

  /// The commands the hook runs when [event] fires.
  required final List<HookCommand> commands,

  /// The plugin's name, as its manifest declares it.
  required final String plugin,

  /// The directory [HookCommand.rootPlaceholder] stands for.
  required final Directory pluginRoot,

  /// Narrows which tools the hook fires for, or null for all of them.
  final String? matcher,

  /// The agent that declared the hook for itself, or null.
  final String? agent,
}) {
  /// {@macro hook_asset}
  this;
}
