import 'package:file/file.dart';

/// {@template hook_command}
/// One command a hook runs when its event fires.
///
/// [command] is kept verbatim, including any `${CLAUDE_PLUGIN_ROOT}`
/// placeholder. Expanding or rewriting it is a translator's job, because only
/// the translator knows where the scripts landed for its harness.
/// {@endtemplate}
class const HookCommand({
  required final String type,
  required final String command,
  final int? timeout,
});

/// {@template hook_asset}
/// One hook registration resolved from a plugin's `hooks/hooks.json`.
///
/// [event] is the lifecycle point, such as `PreToolUse` or `SessionStart`.
/// [matcher] narrows which tools it fires for and is absent on events that do
/// not match against a tool, such as `SessionStart`.
///
/// [directory] is the plugin's `hooks/` directory, so the scripts the commands
/// reference can be copied alongside. It is carried per hook rather than per
/// plugin because merging combines hooks from several plugins.
/// {@endtemplate}
class const HookAsset({
  required final String event,
  required final List<HookCommand> commands,
  required final Directory directory,
  final String? matcher,
});
