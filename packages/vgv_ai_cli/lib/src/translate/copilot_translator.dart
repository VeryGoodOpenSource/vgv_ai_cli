import 'dart:convert';

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
/// Copilot reads `~/.agents/skills` natively and invokes each skill by name,
/// so it needs no commands. Its agents are markdown with frontmatter, and its
/// MCP servers live in their own `mcp-config.json` rather than in settings.
/// {@endtemplate}
class const CopilotTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.copilot;

  @override
  bool get runsHooks => true;

  /// Copilot reads every `*.json` under `~/.copilot/hooks/`, subfolders
  /// included, as a hooks file, so the copied scripts live beside that
  /// folder rather than in it, or a plugin's own JSON would be read as one.
  @override
  Directory hooksRoot(Directory home) {
    final config = harness.configDirectory(home);
    return config.fileSystem.directory(
      p.join(config.path, 'vgv_ai', HookScripts.hooksFolder),
    );
  }

  /// Copilot documents a `type` on every server, so one is written rather
  /// than left for it to infer.
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

  /// The plugins' hooks, as a file under `~/.copilot/hooks/` spells them.
  ///
  /// Copilot reads a hook registered under Claude Code's event name with
  /// Claude Code's matcher semantics and reports the tool under Claude
  /// Code's name, so the events and matchers carry over as written. Three
  /// things are spelled differently here: each command is its own entry
  /// rather than one of a matcher's list, the command sits under `bash` with
  /// its timeout as `timeoutSec`, and an MCP tool is named `<server>-<tool>`
  /// rather than `mcp__<server>__<tool>`. The commands point at Copilot's own
  /// copy of each plugin's `hooks` folder under [hooksRoot], the one
  /// [hookFiles] writes, which is where the payload is answered.
  ///
  /// A hook an agent declared for itself is left out: Copilot's tool payload
  /// names no agent, so there is nothing to scope it by, and a guard meant
  /// for one agent would run for all of them.
  ///
  /// See https://docs.github.com/en/copilot/reference/hooks-reference.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in _runnable(assets)) {
      for (final command in hook.commands) {
        if (command.type != HookScripts.commandType) continue;
        events.putIfAbsent(hook.event, () => []).add({
          'type': command.type,
          'matcher': ?_matcher(hook),
          'bash': HookScripts.command(command, hook, hooksRoot: hooksRoot),
          'timeoutSec': ?command.timeout,
        });
      }
    }
    return events.isEmpty ? null : jsonEncode({'version': 1, 'hooks': events});
  }

  /// Copilot's own copy of each plugin's `hooks` folder, with [preamble] at
  /// the top of every script a hook runs.
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => _scripts.files(_runnable(assets), hooksRoot: hooksRoot);

  /// What [hookFiles] could not copy as intended, and what [hooks] left out.
  @override
  List<TranslationNote> notes(PluginAssets assets) {
    final scoped = assets.hooks.where((hook) => hook.agent != null);
    final handlers = [
      for (final hook in _runnable(assets))
        for (final command in hook.commands)
          if (command.type != HookScripts.commandType) command,
    ];
    return [
      ...super.notes(assets),
      ..._scripts.notes(_runnable(assets)),
      for (final hook in scoped)
        TranslationNote(
          subject: "${hook.agent}'s ${hook.event} hook",
          reason:
              'Copilot names no agent in a tool call, so a hook an agent '
              'declares for itself cannot be scoped to it and is left out',
        ),
      if (handlers.isNotEmpty)
        TranslationNote(
          subject: '${handlers.length} ${handlers.first.type} handler(s)',
          reason: 'Copilot runs a shell command only, so they are left out',
        ),
    ];
  }

  /// What goes at the top of Copilot's copy of a hook script, below its
  /// shebang, so a script written for Claude Code runs as written.
  ///
  /// It answers what Copilot hands a script differently. It sets
  /// `CLAUDE_PLUGIN_ROOT`, which Copilot sets for a plugin's own hooks only,
  /// to the plugin's real location. It names a file's path under
  /// `tool_input.file_path`, which the scripts read, beside `tool_input.path`,
  /// which Copilot sends. It lifts a permission decision the script writes
  /// under `hookSpecificOutput` to the top level, which is where Copilot
  /// reads one. And it lets a failure other than exit 2 through, as Claude
  /// Code does, where Copilot would deny the tool call.
  ///
  /// What a script says is spelled as Copilot reads it. Claude Code takes
  /// plain text at session start and feeds the agent what a script that
  /// exits 2 says on stderr, where Copilot reads JSON alone: so a
  /// session-start message becomes `additionalContext`, and an exit 2 with
  /// nothing on stdout becomes a denial carrying the stderr before a tool
  /// and `additionalContext` carrying it after one. Without jq the payload
  /// and the output pass as they are, and only the exit is answered.
  ///
  /// It is bash, as the plugins' scripts are, so it goes only into a script
  /// bash runs. `__ROOT__` is replaced with the plugin root as one shell word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Copilot. Edits here are overwritten on the next run.
#
# Copilot sets CLAUDE_PLUGIN_ROOT for a plugin's own hooks only, so it is set
# to the plugin's real files. Copilot names a file's path tool_input.path
# where the script reads tool_input.file_path, and denies a tool call on any
# failing exit where Claude Code lets one through. And Copilot reads JSON
# alone where Claude Code reads a decision under hookSpecificOutput, plain
# text at session start, and what a script exiting 2 says on stderr. So the
# script below gets the path under both keys, a failure other than exit 2 is
# let through, and its answer is spelled as Copilot reads it. Without jq the
# payload and the output pass as they are.
export CLAUDE_PLUGIN_ROOT=__ROOT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ]; then
  vgv_payload=$(cat)
  vgv_jq=0
  if command -v jq > /dev/null 2>&1; then
    vgv_jq=1
    vgv_rewritten=$(printf '%s' "$vgv_payload" | jq -c '
      if (.tool_input | type) == "object"
        and (.tool_input | has("path"))
        and (.tool_input | has("file_path") | not)
      then .tool_input.file_path = .tool_input.path else . end
    ' 2> /dev/null) && vgv_payload=$vgv_rewritten
  fi
  vgv_errors=$(mktemp)
  vgv_output=$(printf '%s' "$vgv_payload" \
    | VGV_CLAUDE_PAYLOAD=1 bash "$0" 2> "$vgv_errors")
  vgv_exit=$?
  vgv_stderr=$(cat "$vgv_errors")
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

  /// The prefix Claude Code gives an MCP tool's name, and the separator it
  /// puts between the server and the tool.
  static const _mcpPrefix = 'mcp__';
  static const _mcpSeparator = '__';

  /// The hooks Copilot can run: every one the plugins declare for all agents.
  static List<HookAsset> _runnable(PluginAssets assets) => [
    for (final hook in assets.hooks)
      if (hook.agent == null) hook,
  ];

  /// [hook]'s matcher as Copilot spells it, and null when it declares none,
  /// which is how both harnesses spell a hook that fires for every tool.
  ///
  /// A matcher is an alternation, and each alternative naming an MCP tool is
  /// respelled: Claude Code names one `mcp__<server>__<tool>`, Copilot
  /// `<server>-<tool>`. Every other alternative is a name both spell the
  /// same way, or a pattern over such names, and carries over as written.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => declared.split('|').map(_copilotTool).join('|'),
    _ => null,
  };

  /// [alternative] as Copilot names the tool it matches.
  static String _copilotTool(String alternative) =>
      alternative.startsWith(_mcpPrefix)
      ? alternative.substring(_mcpPrefix.length).replaceAll(_mcpSeparator, '-')
      : alternative;
}
