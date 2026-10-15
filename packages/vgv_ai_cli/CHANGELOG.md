# 0.1.0

- feat: initial release of `vgv_ai`, which configures the VGV plugins,
  `vgv-wingspan` and `vgv-ai-flutter-plugin`, for these coding agent
  harnesses:
  - Claude Code, which installs the plugins natively from the marketplace.
  - Gemini CLI
  - Codex
  - OpenCode
  - Pi
  - GitHub Copilot CLI
  - Antigravity CLI
- feat: `install` configures every detected harness with the plugins' skills,
  agents, commands, MCP servers and hooks, as far as each harness supports
  them. Skills are shared under `~/.agents/skills`. Settings are merged, so
  keys you own are kept, and what was written is recorded in
  `~/.vgv_ai/manifest.json`.
  - `--check` prints what would change without writing anything.
  - `--force` overwrites your values where they conflict with VGV's.
  - `--only <harness>` configures the named harnesses, detected or not, and
    `--no-<harness>` skips one.
- feat: `doctor` reports, per harness, what VGV installed that is missing,
  changed since, or not what this version installs, along with the installed
  and pinned plugin versions. Every problem comes with the `install` command
  that fixes it. It never changes harness config or the manifest, and takes
  `--only` and `--no-<harness>`.
- feat: `uninstall` removes only what the manifest records, keeping your own
  files, keys and sections.
  - `--check` prints what would be removed without removing anything.
  - `--force` also removes what you changed since install.
  - `--only <harness>` and `--no-<harness>` narrow the run.
- feat: `update` updates the CLI to the latest version.
