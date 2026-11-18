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
///
/// The body is four filters, a predicate, and the two ways an answer is
/// reached — what the script printed, or what it complained about when it
/// blocked — so the run itself reads as a list of steps.
const devinCompatScript = r'''
#!/bin/bash
# Sourced at the top of each hook script vgv_ai copies for Devin, so a script
# written for Claude Code runs under Devin CLI. Written by vgv_ai install;
# edits here are overwritten on the next run.
[ -z "${VGV_CLAUDE_PAYLOAD:-}" ] || return 0

# Reads a Devin payload, prints it with the tool named as Claude Code does.
vgv_rename_tool() {
  jq -c '
    {exec: "Bash", edit: "Edit", apply_patch: "Edit", write: "Write",
     read: "Read", glob: "Glob", grep: "Grep"} as $tools
    | if has("tool_name")
      then .tool_name = ($tools[.tool_name] // .tool_name) else . end
  ' 2> /dev/null
}

# Reads what a script printed, prints the decision Devin reads. Prints
# nothing for an `ask`, which Devin has no answer for, and passes any other
# object through as it came.
vgv_as_decision() {
  jq -c '
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
  ' 2> /dev/null
}

# Prints $1 as the context Devin injects on this event.
vgv_as_context() {
  jq -cn --arg event "$vgv_event" --arg text "$1" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $text}}'
}

# Prints $1 as the denial Devin reads before a tool.
vgv_as_block() {
  jq -cn --arg text "$1" '{decision: "block", reason: $text}'
}

# Whether Devin reads injected context on this event.
vgv_injects_context() {
  case "$vgv_event" in
    SessionStart | UserPromptSubmit | PostToolUse) return 0 ;;
  esac
  return 1
}

# Rewrites $vgv_output from what the script printed.
vgv_answer_from_stdout() {
  local decision
  decision=$(printf '%s' "$vgv_output" | vgv_as_decision)
  if [ -n "$decision" ]; then
    vgv_output=$decision
  elif printf '%s' "$vgv_output" | jq -e . > /dev/null 2>&1; then
    # Valid JSON that mapped to nothing: an `ask`, so Devin's own
    # permission handling runs.
    vgv_output=""
  elif vgv_injects_context; then
    vgv_output=$(vgv_as_context "$vgv_output")
  fi
}

# Rewrites $vgv_output, and $vgv_exit where the event only takes context,
# from what the script said as it blocked.
vgv_answer_from_stderr() {
  if [ "$vgv_event" = PreToolUse ]; then
    vgv_output=$(vgv_as_block "$vgv_stderr")
  elif vgv_injects_context; then
    vgv_output=$(vgv_as_context "$vgv_stderr")
    vgv_exit=0
  fi
}

vgv_payload=$(cat)
vgv_event=""
vgv_jq=0
if command -v jq > /dev/null 2>&1; then
  vgv_jq=1
  vgv_event=$(printf '%s' "$vgv_payload" | jq -r '.hook_event_name // ""' \
    2> /dev/null)
  vgv_renamed=$(printf '%s' "$vgv_payload" | vgv_rename_tool) \
    && vgv_payload=$vgv_renamed
fi

vgv_errors=$(mktemp)
vgv_output=$(printf '%s' "$vgv_payload" \
  | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@" 2> "$vgv_errors")
vgv_exit=$?
vgv_stderr=$(cat "$vgv_errors")
rm -f "$vgv_errors"
[ -z "$vgv_stderr" ] || printf '%s\n' "$vgv_stderr" >&2

if [ "$vgv_jq" -eq 1 ]; then
  if [ -n "$vgv_output" ]; then
    vgv_answer_from_stdout
  elif [ "$vgv_exit" -eq 2 ] && [ -n "$vgv_stderr" ]; then
    vgv_answer_from_stderr
  fi
fi
[ -z "$vgv_output" ] || printf '%s\n' "$vgv_output"
exit "$vgv_exit"
''';
