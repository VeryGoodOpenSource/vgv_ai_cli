/// Goes below the shebang of every script a hook runs, in Antigravity's
/// copy of the plugin's hooks folder. `__ROOT__` and `__COMPAT__` are
/// replaced with quoted shell words: the plugin root and the path of
/// [antigravityCompatScript].
const antigravityPreamble = '''
# Added by vgv_ai install so this Claude Code hook script runs under
# Antigravity CLI.
export CLAUDE_PLUGIN_ROOT=__ROOT__
. __COMPAT__
''';

/// The script [antigravityPreamble] sources, written once under the hooks
/// root.
///
/// Antigravity sends `toolCall.name` and `toolCall.args` under its own
/// names, `workspacePaths` for the directory, and no event name, so the
/// script gets Claude Code's payload, with the event from `VGV_HOOK_EVENT`.
/// Its answer is spelled as Antigravity reads it: a permission decision, or
/// an exit 2 with its stderr, becomes the top-level `decision` before a
/// tool; after a tool nothing is read, so `{}` is answered; a session-start
/// line becomes `injectSteps`. Exit codes are undocumented, so the script's
/// is not passed on. Without jq the payload and the output pass as they are.
const antigravityCompatScript = r'''
#!/bin/bash
# Sourced at the top of each hook script vgv_ai copies for Antigravity, so a
# script written for Claude Code runs under Antigravity CLI. Written by
# vgv_ai install; edits here are overwritten on the next run.
[ -z "${VGV_CLAUDE_PAYLOAD:-}" ] || return 0
vgv_payload=$(cat)
vgv_event=${VGV_HOOK_EVENT:-}
vgv_jq=0
if command -v jq > /dev/null 2>&1; then
  vgv_jq=1
  vgv_rewritten=$(printf '%s' "$vgv_payload" | jq -c --arg event "$vgv_event" '
    {run_command: "Bash", write_to_file: "Write", replace_file_content: "Edit",
     multi_replace_file_content: "Edit", view_file: "Read",
     find_by_name: "Glob", grep_search: "Grep", list_dir: "LS"} as $tools
    | (.toolCall.args // {}) as $args
    | {hook_event_name: $event, session_id: (.conversationId // ""),
       transcript_path: (.transcriptPath // ""),
       cwd: (.workspacePaths[0] // "")}
    + (if .toolCall then
        {tool_name: ($tools[.toolCall.name] // .toolCall.name),
         tool_input: ($args
           + (if $args.CommandLine then {command: $args.CommandLine}
              else {} end)
           + (if $args.TargetFile then {file_path: $args.TargetFile}
              else {} end)
           + (if $args.AbsolutePath then {file_path: $args.AbsolutePath}
              else {} end))}
       else {} end)
  ' 2> /dev/null) && vgv_payload=$vgv_rewritten
fi
vgv_errors=$(mktemp)
vgv_output=$(printf '%s' "$vgv_payload" \
  | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@" 2> "$vgv_errors")
vgv_exit=$?
vgv_stderr=$(cat "$vgv_errors")
rm -f "$vgv_errors"
[ -z "$vgv_stderr" ] || printf '%s\n' "$vgv_stderr" >&2
if [ "$vgv_jq" -eq 1 ]; then
  case "$vgv_event" in
    PreToolUse)
      vgv_answer=$(printf '%s' "$vgv_output" | jq -c '
        if (.hookSpecificOutput | type) == "object"
          and (.hookSpecificOutput | has("permissionDecision"))
        then .hookSpecificOutput
          | {decision: .permissionDecision}
            + (if has("permissionDecisionReason")
               then {reason: .permissionDecisionReason} else {} end)
        else . end
      ' 2> /dev/null) && vgv_output=$vgv_answer
      if [ -z "$vgv_answer" ] && [ "$vgv_exit" -eq 2 ] \
        && [ -n "$vgv_stderr" ]; then
        vgv_output=$(jq -cn --arg text "$vgv_stderr" \
          '{decision: "deny", reason: $text}')
      fi
      ;;
    PostToolUse)
      vgv_output='{}'
      ;;
    SessionStart)
      if [ -n "$vgv_output" ]; then
        vgv_output=$(jq -cn --arg text "$vgv_output" \
          '{injectSteps: [{systemMessage: $text}]}')
      fi
      ;;
  esac
fi
[ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
exit 0
''';
