/// Goes below the shebang of every script a hook runs, in Devin's copy of
/// the plugin's hooks folder. `__ROOT__` and `__COMPAT__` are replaced with
/// quoted shell words: the plugin root and the path of [devinCompatScript].
const devinPreamble = '''
# Added by vgv_ai install so this Claude Code hook script runs under Devin.
export CLAUDE_PLUGIN_ROOT=__ROOT__
. __COMPAT__
''';

/// The script [devinPreamble] sources, written once under the hooks root.
///
/// Devin already sends Claude Code's payload field for field —
/// `hook_event_name`, `tool_input.file_path`, `tool_input.command` — so only
/// the tool name is rewritten, from Devin's lowercase names to the ones the
/// scripts compare against.
///
/// The answer is what differs: Devin reads a top-level `decision` of
/// `approve` or `block` with a `reason`, rather than Claude Code's
/// `hookSpecificOutput.permissionDecision`, and it takes injected text as
/// `hookSpecificOutput.additionalContext` tagged with the event name, which
/// a Claude Code script prints as bare stdout. An `ask` decision is dropped
/// so Devin's own permission handling runs. Without jq the payload and the
/// output pass as they are.
const devinCompatScript = r'''
#!/bin/bash
# Sourced at the top of each hook script vgv_ai copies for Devin, so a script
# written for Claude Code runs under Devin CLI. Written by vgv_ai install;
# edits here are overwritten on the next run.
[ -z "${VGV_CLAUDE_PAYLOAD:-}" ] || return 0
vgv_payload=$(cat)
vgv_event=""
vgv_jq=0
if command -v jq > /dev/null 2>&1; then
  vgv_jq=1
  vgv_event=$(printf '%s' "$vgv_payload" | jq -r '.hook_event_name // ""' \
    2> /dev/null)
  vgv_rewritten=$(printf '%s' "$vgv_payload" | jq -c '
    {exec: "Bash", edit: "Edit", apply_patch: "Edit", write: "Write",
     read: "Read", glob: "Glob", grep: "Grep"} as $tools
    | if has("tool_name")
      then .tool_name = ($tools[.tool_name] // .tool_name) else . end
  ' 2> /dev/null) && vgv_payload=$vgv_rewritten
fi
vgv_errors=$(mktemp)
vgv_output=$(printf '%s' "$vgv_payload" \
  | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@" 2> "$vgv_errors")
vgv_exit=$?
vgv_stderr=$(cat "$vgv_errors")
rm -f "$vgv_errors"
[ -z "$vgv_stderr" ] || printf '%s\n' "$vgv_stderr" >&2
# The events Devin injects additionalContext for.
vgv_injects=0
case "$vgv_event" in
  SessionStart | UserPromptSubmit | PostToolUse) vgv_injects=1 ;;
esac
if [ "$vgv_jq" -eq 1 ]; then
  if [ -n "$vgv_output" ]; then
    vgv_answer=$(printf '%s' "$vgv_output" | jq -c '
      if (.hookSpecificOutput | type) == "object"
        and (.hookSpecificOutput | has("permissionDecision"))
      then .hookSpecificOutput
        | {allow: "approve", deny: "block"} as $decisions
        | if $decisions[.permissionDecision] then
            {decision: $decisions[.permissionDecision]}
            + (if has("permissionDecisionReason")
               then {reason: .permissionDecisionReason} else {} end)
          else empty end
      else . end
    ' 2> /dev/null)
    if [ -n "$vgv_answer" ]; then
      vgv_output=$vgv_answer
    elif printf '%s' "$vgv_output" | jq -e . > /dev/null 2>&1; then
      # Valid JSON that mapped to nothing: an `ask`, which Devin has no
      # answer for, so its own permission handling runs.
      vgv_output=""
    elif [ "$vgv_injects" -eq 1 ]; then
      vgv_output=$(jq -cn --arg event "$vgv_event" --arg text "$vgv_output" \
        '{hookSpecificOutput:
          {hookEventName: $event, additionalContext: $text}}')
    fi
  elif [ "$vgv_exit" -eq 2 ] && [ -n "$vgv_stderr" ]; then
    case "$vgv_event" in
      PreToolUse)
        vgv_output=$(jq -cn --arg text "$vgv_stderr" \
          '{decision: "block", reason: $text}')
        ;;
      *)
        if [ "$vgv_injects" -eq 1 ]; then
          vgv_output=$(jq -cn --arg event "$vgv_event" \
            --arg text "$vgv_stderr" \
            '{hookSpecificOutput:
              {hookEventName: $event, additionalContext: $text}}')
          vgv_exit=0
        fi
        ;;
    esac
  fi
fi
[ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
exit "$vgv_exit"
''';
