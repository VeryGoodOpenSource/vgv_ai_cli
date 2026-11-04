#!/usr/bin/env bash
# Audits a Claude Code plugin checkout before it is pinned in vgvPlugins.
# shellcheck disable=SC2016 # ${CLAUDE_PLUGIN_ROOT} is literal text here.
#
# Usage: audit_plugin.sh <plugin-dir> [pinned-plugin-dir...]
#
# Pass the checkouts of the plugins already pinned to also check for skill,
# agent and MCP server names the new plugin shares with them. Prints findings
# only; it never edits anything. Needs rg and jq.
set -euo pipefail

if [[ $# -lt 1 || ! -d "$1" ]]; then
  echo "usage: $0 <plugin-dir> [pinned-plugin-dir...]" >&2
  exit 64
fi

plugin=$1
shift

section() { printf '\n== %s\n' "$1"; }

# Skill names: the frontmatter name, else the folder name.
skill_names() {
  local dir=$1 file name
  [[ -d "$dir/skills" ]] || return 0
  for file in "$dir"/skills/*/SKILL.md; do
    [[ -f "$file" ]] || continue
    name=$(sed -n '2,/^---$/{s/^name:[[:space:]]*//p;}' "$file" | head -1 | tr -d "\"'")
    echo "${name:-$(basename "$(dirname "$file")")}"
  done
}

# Agent names: the frontmatter name, else the file name.
agent_names() {
  local dir=$1 file name
  [[ -d "$dir/agents" ]] || return 0
  while IFS= read -r file; do
    name=$(sed -n '2,/^---$/{s/^name:[[:space:]]*//p;}' "$file" | head -1 | tr -d "\"'")
    echo "${name:-$(basename "$file" .md)}"
  done < <(find "$dir/agents" -name '*.md' -type f)
}

mcp_names() {
  local file=$1/.mcp.json
  [[ -f "$file" ]] && jq -r '.mcpServers // {} | keys[]' "$file"
  return 0
}

section 'Manifest'
manifest=$plugin/.claude-plugin/plugin.json
if [[ -f "$manifest" ]]; then
  jq -r '"name: \(.name)\nversion: \(.version)"' "$manifest"
else
  echo 'MISSING .claude-plugin/plugin.json'
fi

section 'Top-level entries the parser does not read'
# The parser reads skills/, agents/, hooks/hooks.json, .mcp.json and
# .claude-plugin/plugin.json. Anything else either is read in place through
# ${CLAUDE_PLUGIN_ROOT} (references/, scripts/) or is silently not ported.
for entry in "$plugin"/* "$plugin"/.[!.]*; do
  [[ -e "$entry" ]] || continue
  case $(basename "$entry") in
    skills | agents | hooks | .mcp.json | .claude-plugin | .git | .github) ;;
    *.md | LICENSE* | *.yaml | *.yml | .gitignore) ;;
    *) basename "$entry" ;;
  esac
done

section 'Contributes'
echo "skills: $(skill_names "$plugin" | xargs)"
echo "agents: $(agent_names "$plugin" | xargs)"
echo "mcp servers: $(mcp_names "$plugin" | xargs)"
if [[ -f "$plugin/hooks/hooks.json" ]]; then
  echo "hook events: $(jq -r '.hooks // {} | keys[]' "$plugin/hooks/hooks.json" | xargs)"
  echo "hook handler types: $(jq -r '[.hooks // {} | .[][] | .hooks[] | .type // "command"] | unique[]' \
    "$plugin/hooks/hooks.json" | xargs)"
else
  echo 'hook events: none'
fi

section '${CLAUDE_PLUGIN_ROOT} in files that are copied, not rewritten'
# Bodies of SKILL.md and agent files are rewritten, and hooks.json is
# translated. Any other file a skill ships is copied byte for byte, so the
# placeholder there never resolves outside Claude Code.
rg -n --no-heading -F '${CLAUDE_PLUGIN_ROOT}' "$plugin/skills" 2>/dev/null |
  rg -v '/SKILL\.md:' || echo 'none'

section 'Bare paths to plugin files in skill and agent bodies'
# A path such as references/x.md with no ${CLAUDE_PLUGIN_ROOT}/ before it
# resolves against the user's project, not the plugin. An upstream issue.
tops=()
for entry in "$plugin"/*/; do
  case $(basename "$entry") in
    skills | agents | hooks) ;;
    *) tops+=("$(basename "$entry")") ;;
  esac
done
if [[ ${#tops[@]} -eq 0 ]]; then
  echo 'none'
else
  pattern="(^|[\`'\" (])($(IFS='|'; echo "${tops[*]}"))/[^\`'\" )]*"
  { rg -o --no-heading -e "$pattern" "$plugin/skills" "$plugin/agents" 2>/dev/null || true; } |
    sed -E "s|^$plugin/||; s|:[\`'\" (]|:|" | sort | uniq -c | sort -rn |
    awk '{ print }
         END { if (NR == 0) print "none" }'
fi

section 'Paths through ${CLAUDE_PLUGIN_ROOT} that the plugin does not hold'
missing=0
while IFS= read -r path; do
  if [[ ! -e "$plugin/$path" ]]; then
    echo "MISSING $path"
    missing=1
  fi
done < <(rg -o --no-filename -e '[$][{]CLAUDE_PLUGIN_ROOT[}]/[^ `"'"'"')]*[^ `"'"'"').,;:]' \
  "$plugin/skills" "$plugin/agents" 2>/dev/null | sed 's|^[$]{CLAUDE_PLUGIN_ROOT}/||' | sort -u)
[[ $missing -eq 1 ]] || echo 'none'

if [[ $# -gt 0 ]]; then
  section 'Names already taken by a pinned plugin (the first pin wins)'
  clash=0
  for kind in skill agent mcp; do
    taken=$(for other in "$@"; do "${kind}_names" "$other"; done | sort -u)
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if grep -qxF "$name" <<<"$taken"; then
        echo "$kind $name"
        clash=1
      fi
    done < <("${kind}_names" "$plugin")
  done
  [[ $clash -eq 1 ]] || echo 'none'
fi
