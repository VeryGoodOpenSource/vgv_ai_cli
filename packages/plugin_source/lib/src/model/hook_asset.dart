import 'package:file/file.dart';

/// {@template hook_command}
/// One command a hook runs when its event fires.
///
/// [command] is a shell command. Where it references the plugin's own files it
/// uses the [pluginRoot] placeholder, which no harness understands natively;
/// substituting the real location is a translator's job.
/// {@endtemplate}
class const HookCommand({
  required final String type,
  required final String command,
  final int? timeout,
}) {
  /// Stands in for the plugin's root directory inside [command].
  ///
  /// Parsers rewrite their harness's own placeholder to this one, so
  /// translators substitute exactly one token regardless of where a plugin
  /// came from.
  static const pluginRoot = r'${PLUGIN_ROOT}';
}

/// {@template hook_asset}
/// One hook registration resolved from a plugin.
///
/// [event] is the lifecycle point, carried as the source harness names it.
/// [matcher] narrows which tools it fires for. [directory] holds the scripts
/// the commands reference, carried per hook because merging combines several.
/// {@endtemplate}
class const HookAsset({
  required final String event,
  required final List<HookCommand> commands,
  required final Directory directory,
  final String? matcher,
});
