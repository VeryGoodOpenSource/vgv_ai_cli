# 0.1.0+1

- feat: initial brick rendering the files each harness reads to use the VGV
  plugins, one folder per harness, rendered only when its flag is set:
  - `claude/`: `settings.json` pointing Claude Code at the marketplace.
  - `gemini/`: `settings.json`, `AGENTS.md`, `agents/*.md` and
    `commands/*.toml`.
  - `codex/`: `config.toml`, `AGENTS.md`, `agents/*.toml`, and `hooks.json`
    when the CLI supplies hooks for Codex to run.
  - `opencode/`: `opencode.json`, `AGENTS.md`, `agent/*.md` and
    `command/*.md`.
  - `pi/`: `AGENTS.md`, indexing the skills only, and `prompts/*.md`.
  - `copilot/`: `mcp-config.json`, `copilot-instructions.md`,
    `agents/*.agent.md`, and `hooks/vgv.json` when the CLI supplies hooks.
  - `antigravity/`: the `plugins/vgv/` plugin, with `plugin.json`,
    `mcp_config.json`, `agents/*.md`, and `hooks.json` when the CLI supplies
    hooks.
