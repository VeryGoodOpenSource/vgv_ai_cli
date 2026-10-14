/// Goes below the shebang of every script a hook runs, in Codex's copy of
/// the plugin's hooks folder. `__ROOT__`, `__AGENT__` and `__COMPAT__` are
/// replaced with quoted shell words: the plugin root, the agent the hook is
/// scoped to or an empty string, and the path of [codexCompatScript].
const codexPreamble = '''
# Added by vgv_ai install so this Claude Code hook script runs under Codex.
export CLAUDE_PLUGIN_ROOT=__ROOT__
VGV_AGENT=__AGENT__ . __COMPAT__
''';

/// The script [codexPreamble] sources, written once under the hooks root.
const codexCompatScript = r'''
#!/bin/bash
# Sourced at the top of each hook script vgv_ai copies into ~/.codex/hooks, so
# a script written for Claude Code runs under Codex. Written by vgv_ai install;
# edits here are overwritten on the next run.
#
# A script scoped to VGV_AGENT runs only when the payload's agent_type is that
# agent. An apply_patch names no file, so the script re-runs once per file of
# the patch with the Edit or Write payload Claude Code would have sent, and
# the most restrictive answer wins. Anything else, and everything without jq,
# reaches the script as it came.
if [ -n "${VGV_CLAUDE_PAYLOAD:-}" ] || ! command -v jq > /dev/null 2>&1; then
  return 0
fi
vgv_payload=$(cat)

if [ -n "${VGV_AGENT:-}" ]; then
  vgv_caller=$(printf '%s' "$vgv_payload" | jq -r '.agent_type // ""')
  [ "$vgv_caller" = "$VGV_AGENT" ] || exit 0
fi

# One "tool<TAB>path" line per file of an apply_patch, paths resolved against
# the payload's cwd. Any other tool yields no lines.
vgv_edits=$(printf '%s' "$vgv_payload" | jq -r '
  select(.tool_name == "apply_patch")
  | ((.cwd // ".") | rtrimstr("/")) as $cwd
  | .tool_input.command // ""
  | scan("(?m)^\\*\\*\\* (Add File|Update File|Move to): (.+)$")
  | (if .[0] == "Add File" then "Write" else "Edit" end)
    + "\t" + (.[1] | if startswith("/") then . else $cwd + "/" + . end)
' 2> /dev/null)
vgv_event=$(printf '%s' "$vgv_payload" | jq -r '.hook_event_name // ""')

# Whether an answer denies or blocks.
vgv_denies() {
  printf '%s' "$1" | jq -e '
    (.hookSpecificOutput.permissionDecision // .decision) as $d
    | $d == "deny" or $d == "block"
  ' > /dev/null 2>&1
}

vgv_status=0
vgv_answer=""
vgv_denied=0
vgv_ran=0
while IFS=$'\t' read -r vgv_tool vgv_file; do
  [ -n "$vgv_file" ] || continue
  # After the tool ran, a deleted or renamed-away file is gone; before it, a
  # file it adds is not there yet. So only PostToolUse checks the disk.
  if [ "$vgv_event" = "PostToolUse" ] && [ ! -f "$vgv_file" ]; then continue; fi
  vgv_ran=1
  vgv_output=$(printf '%s' "$vgv_payload" \
    | jq --arg tool "$vgv_tool" --arg file "$vgv_file" \
      '.tool_name = $tool | .tool_input.file_path = $file' \
    | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@")
  vgv_code=$?
  # A deny wins over a failure, a failure over an answer that passed.
  if vgv_denies "$vgv_output"; then
    [ "$vgv_denied" -eq 1 ] || { vgv_denied=1; vgv_answer=$vgv_output; }
  elif [ "$vgv_code" -ne 0 ] && [ "$vgv_status" -eq 0 ]; then
    vgv_status=$vgv_code
    [ "$vgv_denied" -eq 1 ] || vgv_answer=$vgv_output
  elif [ -z "$vgv_answer" ] && [ "$vgv_status" -eq 0 ]; then
    vgv_answer=$vgv_output
  fi
done <<< "$vgv_edits"

if [ "$vgv_ran" -eq 0 ]; then
  printf '%s' "$vgv_payload" | VGV_CLAUDE_PAYLOAD=1 bash "$0" "$@"
  exit $?
fi
[ -z "$vgv_answer" ] || printf '%s\n' "$vgv_answer"
exit "$vgv_status"
''';
