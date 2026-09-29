# 0.2.0+1

- refactor: own the per-harness layout. Agents, commands and prompts are
  rendered into each harness's own directories, and a directory a harness
  lacks is simply absent from its tree.
- refactor: take finished settings strings from the CLI and drop the
  `pre_gen` hook and its models.
- feat: render `AGENTS.md` for Pi, which reads it from `~/.pi/agent`. It
  indexes the skills only, since Pi has no subagents to delegate to.
- fix: drop `pi/settings.json`. Pi reads `~/.agents/skills` natively, so its
  only entry was redundant.

# 0.1.0+1

- feat: initial brick generating staging output for Claude Code, Gemini CLI,
  Codex, OpenCode and Pi.
