---
name: flutter-reviewer
description: >
  Read-only Flutter reviewer.
tools: Read, Glob, Grep
skills:
  - testing
  - animations
model: inherit
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash allow-readonly-git.sh"
---

Review the diff.
