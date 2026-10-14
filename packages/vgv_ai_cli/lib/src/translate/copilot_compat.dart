/// Goes below the shebang of every script a hook runs, in Copilot's copy of
/// the plugin's hooks folder. `__ROOT__` and `__COMPAT__` are replaced with
/// quoted shell words: the plugin root and the path of
/// [copilotCompatScript].
const copilotPreamble = '''
# Added by vgv_ai install so this Claude Code hook script runs under Copilot.
export CLAUDE_PLUGIN_ROOT=__ROOT__
. __COMPAT__
''';

/// The script [copilotPreamble] sources, written once under the hooks root.
///
/// It hands the script each edited file under `tool_input.file_path`
/// (Copilot names one as `tool_input.path`, or sends a whole patch as
/// `tool_input` and the script runs once per file on disk), spells the
/// answer as Copilot reads it (a flat permission decision, `additionalContext`
/// for a session-start message or an exit 2 after a tool, a denial for an
/// exit 2 before one), and lets any other failing exit through, as Claude
/// Code does. Without jq only the exit is answered.
const copilotCompatScript = r'''
#!/bin/bash
# Sourced at the top of each hook script vgv_ai copies for Copilot, so a
# script written for Claude Code runs under Copilot. Written by vgv_ai
# install; edits here are overwritten on the next run.
[ -z "${VGV_CLAUDE_PAYLOAD:-}" ] || return 0
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
    | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@" 2> "$vgv_errors")
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
''';
