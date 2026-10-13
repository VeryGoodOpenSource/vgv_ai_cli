/// Goes below the shebang of every script a hook runs, so a script written
/// for Claude Code runs as written: it sets `CLAUDE_PLUGIN_ROOT`, re-runs
/// the script once per file of an `apply_patch` with the `Edit` or `Write`
/// payload Claude Code would have sent, and stands aside for any agent but
/// the one a scoped hook names. `__ROOT__` and `__AGENT__` are replaced
/// with quoted shell words.
const codexPreamble = r'''
# Added by vgv_ai install so this Claude Code hook script runs under Codex.
# Edits here are overwritten on the next run.
export CLAUDE_PLUGIN_ROOT=__ROOT__
vgv_agent=__AGENT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ] && command -v jq > /dev/null 2>&1; then
  vgv_payload=$(cat)
  # A hook scoped to an agent runs for that agent alone.
  if [ -n "$vgv_agent" ]; then
    vgv_caller=$(printf '%s' "$vgv_payload" | jq -r '.agent_type // ""')
    [ "$vgv_caller" = "$vgv_agent" ] || exit 0
  fi
  # One "tool<TAB>path" line per file an apply_patch touches, as Claude Code
  # would have sent it, paths resolved against the payload's cwd.
  vgv_edits=$(printf '%s' "$vgv_payload" | jq -r '
    select(.tool_name == "apply_patch")
    | ((.cwd // ".") | rtrimstr("/")) as $cwd
    | .tool_input.command // ""
    | scan("(?m)^\\*\\*\\* (Add File|Update File|Move to): (.+)$")
    | (if .[0] == "Add File" then "Write" else "Edit" end)
      + "\t" + (.[1] | if startswith("/") then . else $cwd + "/" + . end)
  ' 2> /dev/null)
  vgv_status=0
  vgv_answer=""
  vgv_ran=0
  while IFS=$'\t' read -r vgv_tool vgv_file; do
    # Skip a file not on disk: deleted, renamed away, or not yet added.
    [ -n "$vgv_file" ] && [ -f "$vgv_file" ] || continue
    vgv_ran=1
    vgv_output=$(printf '%s' "$vgv_payload" \
      | jq --arg tool "$vgv_tool" --arg file "$vgv_file" \
        '.tool_name = $tool | .tool_input.file_path = $file' \
      | VGV_CLAUDE_PAYLOAD=1 bash "$0")
    vgv_exit=$?
    [ "$vgv_status" -ne 0 ] || vgv_status=$vgv_exit
    [ -n "$vgv_answer" ] || vgv_answer=$vgv_output
  done <<< "$vgv_edits"
  if [ "$vgv_ran" -eq 0 ]; then
    printf '%s' "$vgv_payload" | VGV_CLAUDE_PAYLOAD=1 bash "$0"
    exit $?
  fi
  [ -z "$vgv_answer" ] || printf '%s\n' "$vgv_answer"
  exit "$vgv_status"
fi
''';
