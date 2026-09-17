---
name: flat-agent
description: >
  A flat agent whose description uses a folded scalar.
  This second line folds into the first.
tools: Read, Glob, Bash
model: inherit
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard.sh"
---

# Flat agent

Lives directly under `agents/`, the way `vgv-ai-flutter-plugin` ships its only
agent.
