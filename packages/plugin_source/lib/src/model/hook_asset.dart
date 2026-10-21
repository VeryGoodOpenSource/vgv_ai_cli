import 'package:file/file.dart';

/// {@template hook_command}
/// One command a hook runs when its event fires.
///
/// [type] is the handler type as the source harness names it, such as
/// `command`. [timeout] is in seconds, or null for the harness default.
/// [command] is a shell command. Where it references the plugin's own files it
/// uses the [rootPlaceholder], which no harness understands natively;
/// substituting the real location is a translator's job.
/// {@endtemplate}
class const HookCommand({
  required final String type,
  required final String command,
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
  required final String event,
  required final List<HookCommand> commands,
  required final String plugin,
  required final Directory pluginRoot,
  final String? matcher,
  final String? agent,
}) {
  /// {@macro hook_asset}
  this;
}
