import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/hook_scripts.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template copilot_translator}
/// Configures GitHub Copilot CLI.
///
/// Copilot reads `~/.agents/skills` natively and invokes skills by name, so
/// it needs no commands.
/// {@endtemplate}
class const CopilotTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.copilot;

  @override
  bool get runsHooks => true;

  /// Copilot reads every `*.json` under `~/.copilot/hooks/` recursively as
  /// a hooks file, so the script copies live beside that folder.
  @override
  Directory hooksRoot(Directory home) {
    final config = harness.configDirectory(home);
    return config.fileSystem.directory(
      p.join(config.path, 'vgv_ai', HookScripts.hooksFolder),
    );
  }

  /// Copilot documents a `type` on every server.
  @override
  String settings(PluginAssets assets) => jsonEncode({
    'mcpServers': {
      for (final server in assets.mcpServers)
        server.name: {
          'type': switch (server) {
            LocalMCPServer() => 'local',
            RemoteMCPServer() => 'http',
          },
          ...server.toJson(),
        },
    },
  });

  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        frontmatter: Frontmatter.render({
          'name': agent.name,
          'description': agent.description,
        }),
      );

  /// The plugins' hooks, as `~/.copilot/hooks/vgv.json` spells them.
  ///
  /// Under Claude Code's event names, Copilot applies Claude Code's matcher
  /// semantics and tool names, so both carry over. Each command is its own
  /// entry, and a hook an agent declared for itself is left out, since
  /// Copilot's payload names no agent to scope it by.
  ///
  /// See https://docs.github.com/en/copilot/reference/hooks-reference.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in _runnable(assets)) {
      events
          .putIfAbsent(hook.event, () => [])
          .addAll(_entries(hook, hooksRoot: hooksRoot));
    }
    return events.isEmpty ? null : jsonEncode({'version': 1, 'hooks': events});
  }

  /// One entry per shell command of [hook].
  static List<Object?> _entries(
    HookAsset hook, {
    required Directory hooksRoot,
  }) => [
    for (final command in hook.commands)
      if (command.type == HookScripts.commandType)
        {
          'type': command.type,
          'matcher': ?_matcher(hook),
          'bash': HookScripts.command(command, hook, hooksRoot: hooksRoot),
          'timeoutSec': ?command.timeout,
        },
  ];

  /// Copilot's copy of the plugins' hook scripts, with [preamble] on top.
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => _scripts.files(_runnable(assets), hooksRoot: hooksRoot);

  /// What [hookFiles] could not copy as intended, and what [hooks] left out.
  @override
  List<TranslationNote> notes(PluginAssets assets) {
    final runnable = _runnable(assets);
    return [
      ...super.notes(assets),
      ..._scripts.notes(runnable),
      ..._scopedNotes(assets),
      ..._handlerNotes(runnable),
    ];
  }

  /// One note per hook an agent declared for itself.
  static List<TranslationNote> _scopedNotes(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (hook.agent != null)
        TranslationNote(
          subject: "${hook.agent}'s ${hook.event} hook",
          reason:
              'Copilot names no agent in a tool call, so a hook an agent '
              'declares for itself cannot be scoped to it and is left out',
        ),
  ];

  /// One note per handler type that runs no shell command.
  static List<TranslationNote> _handlerNotes(List<HookAsset> hooks) {
    final counts = hooks
        .expand((hook) => hook.commands)
        .map((command) => command.type)
        .where((type) => type != HookScripts.commandType)
        .groupFoldBy<String, int>(
          (type) => type,
          (count, _) => (count ?? 0) + 1,
        );
    return [
      for (final MapEntry(key: type, value: count) in counts.entries)
        TranslationNote(
          subject: '$count $type handler(s)',
          reason: 'Copilot runs a shell command only, so they are left out',
        ),
    ];
  }

  /// Bash inserted below the shebang of a copied script so one written for
  /// Claude Code runs under Copilot.
  ///
  /// It sets `CLAUDE_PLUGIN_ROOT`, hands the script each edited file under
  /// `tool_input.file_path` (Copilot names one as `tool_input.path`, or
  /// sends a whole patch as `tool_input` and the script runs once per file
  /// on disk), spells the answer as Copilot reads it (a flat permission
  /// decision, `additionalContext` for a session-start message or an exit 2
  /// after a tool, a denial for an exit 2 before one), and lets any other
  /// failing exit through, as Claude Code does. Without jq only the exit is
  /// answered. `__ROOT__` is replaced with the plugin root as one shell word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Copilot. Edits here are overwritten on the next run.
export CLAUDE_PLUGIN_ROOT=__ROOT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ]; then
  vgv_payload=$(cat)
  vgv_jq=0
  vgv_runs=""
  if command -v jq > /dev/null 2>&1; then
    vgv_jq=1
    # One payload per file: the file Copilot names under tool_input.path, or
    # each file on disk that a patch sent as tool_input touches.
    vgv_edits=$(printf '%s' "$vgv_payload" | jq -r '
      select(.tool_input | type == "string")
      | ((.cwd // ".") | rtrimstr("/")) as $cwd
      | .tool_input
      | scan("(?m)^\\*\\*\\* (Add File|Update File|Move to): (.+)$")
      | (if .[0] == "Add File" then "Write" else "Edit" end)
        + "\t" + (.[1] | if startswith("/") then . else $cwd + "/" + . end)
    ' 2> /dev/null)
    while IFS=$'\t' read -r vgv_tool vgv_file; do
      [ -n "$vgv_file" ] && [ -f "$vgv_file" ] || continue
      vgv_runs="$vgv_runs$(printf '%s' "$vgv_payload" \
        | jq -c --arg tool "$vgv_tool" --arg file "$vgv_file" \
          '.tool_name = $tool | .tool_input = {file_path: $file}')
"
    done <<< "$vgv_edits"
    if [ -z "$vgv_runs" ]; then
      vgv_runs=$(printf '%s' "$vgv_payload" | jq -c '
        if (.tool_input | type) == "object"
          and (.tool_input | has("path"))
          and (.tool_input | has("file_path") | not)
        then .tool_input.file_path = .tool_input.path else . end
      ' 2> /dev/null)
    fi
  fi
  [ -n "$vgv_runs" ] || vgv_runs=$vgv_payload
  vgv_exit=0
  vgv_output=""
  vgv_stderr=""
  vgv_errors=$(mktemp)
  while IFS= read -r vgv_run; do
    [ -n "$vgv_run" ] || continue
    vgv_one=$(printf '%s' "$vgv_run" \
      | VGV_CLAUDE_PAYLOAD=1 bash "$0" 2> "$vgv_errors")
    vgv_code=$?
    [ "$vgv_exit" -ne 0 ] || vgv_exit=$vgv_code
    [ -n "$vgv_output" ] || vgv_output=$vgv_one
    vgv_more=$(cat "$vgv_errors")
    [ -z "$vgv_more" ] || vgv_stderr="${vgv_stderr:+$vgv_stderr
}$vgv_more"
  done <<< "$vgv_runs"
  rm -f "$vgv_errors"
  [ -z "$vgv_stderr" ] || printf '%s\n' "$vgv_stderr" >&2
  if [ "$vgv_jq" -eq 1 ]; then
    vgv_event=$(printf '%s' "$vgv_payload" \
      | jq -r '.hook_event_name // ""' 2> /dev/null)
    if [ -n "$vgv_output" ]; then
      vgv_answer=$(printf '%s' "$vgv_output" | jq -c '
        if (.hookSpecificOutput | type) == "object"
          and (.hookSpecificOutput | has("permissionDecision"))
        then .hookSpecificOutput
          | {permissionDecision}
            + (if has("permissionDecisionReason")
               then {permissionDecisionReason} else {} end)
        else . end
      ' 2> /dev/null) && vgv_output=$vgv_answer
      if [ -z "$vgv_answer" ] && [ "$vgv_event" = "SessionStart" ]; then
        vgv_output=$(jq -cn --arg text "$vgv_output" \
          '{additionalContext: $text}')
      fi
    elif [ "$vgv_exit" -eq 2 ] && [ -n "$vgv_stderr" ]; then
      case "$vgv_event" in
        PreToolUse)
          vgv_output=$(jq -cn --arg text "$vgv_stderr" \
            '{permissionDecision: "deny", permissionDecisionReason: $text}')
          ;;
        PostToolUse)
          vgv_output=$(jq -cn --arg text "$vgv_stderr" \
            '{additionalContext: $text}')
          vgv_exit=0
          ;;
      esac
    fi
  fi
  [ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
  case "$vgv_exit" in
    0 | 2) exit "$vgv_exit" ;;
    *) exit 0 ;;
  esac
fi
''';

  static const _scripts = HookScripts(
    harness: Harness.copilot,
    preamble: preamble,
  );

  /// How Claude Code names an MCP tool: `mcp__<server>__<tool>`.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks not scoped to an agent.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (hook.agent == null) hook,
  ];

  /// [hook]'s matcher with each MCP tool respelled as Copilot names it,
  /// `<server>-<tool>`. Read as a top-level alternation, which is how the
  /// plugins write theirs.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_copilotTool).join('|'),
    _ => null,
  };

  static String _copilotTool(String alternative) =>
      alternative.startsWith(_mcpPrefix)
      ? alternative.substring(_mcpPrefix.length).replaceAll(_mcpSeparator, '-')
      : alternative;
}
