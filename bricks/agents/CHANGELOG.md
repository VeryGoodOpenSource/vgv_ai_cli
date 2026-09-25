# 0.2.0+1

- refactor: own the per-harness layout. Agents, commands and prompts are
  rendered into each harness's own directories, and a directory a harness
  lacks is simply absent from its tree.
- refactor: take finished settings strings from the CLI and drop the
  `pre_gen` hook and its models.
- fix: drop `codex/AGENTS.md`, which Codex never reads.

# 0.1.0+1

- feat: initial brick generating staging output for Claude Code, Gemini CLI,
  Codex, OpenCode and Pi.
