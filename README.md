# vgv_ai_cli

A CLI that configures Very Good AI coding agents and tooling.

This is a [pub workspace][pub_workspace_link] monorepo. The CLI lives in
[`packages/vgv_ai_cli`](packages/vgv_ai_cli) — see its README for installation and usage.

## Contributor setup

[CONTRIBUTING.md](CONTRIBUTING.md) covers the commands, conventions, and PR rules, and
[ADDING_A_HARNESS.md](ADDING_A_HARNESS.md) walks through adding a new coding agent.

Install the prerequisites listed in [AGENTS.md](AGENTS.md#prerequisites) first. The Dart version
matters more than it looks: on 3.12 the analyze hook reports errors against this codebase's
Dart 3.13 syntax, and those errors read as real ones.

This repo ships a committed agent configuration in `.claude/settings.json`, which declares the
`very-good-claude-code-marketplace` and enables the two VGV plugins described in
[AGENTS.md](AGENTS.md#agent-tooling).

### 1. Trust the folder

Open the repo in Claude Code and accept the trust prompt. The marketplace resolves from the
committed settings — you do **not** need to run `/plugin marketplace add`.

One exception: if you already have a marketplace registered under the name
`very-good-claude-code-marketplace`, that registration wins and the committed pin is ignored.
Check `/plugin` shows the GitHub source; if it shows a local directory instead, remove yours
first.

### 2. Confirm the plugins installed, then restart

Run `/plugin` and check that both plugins show as enabled. Then restart the session: settings
apply immediately, but hooks and MCP servers only bind at session start.

This step is not optional bookkeeping. Wingspan normally nudges you when a companion plugin is
missing, but it decides "already installed" by looking for the plugin name in
`.claude/settings.json` — which this repo commits. If your install silently failed, nothing will
tell you, and the agent will carry on without the hooks or quality gates.

### 3. Verify

From `packages/vgv_ai_cli`:

```bash
dart pub get && dart analyze --fatal-infos --fatal-warnings lib test
```

For the full test and coverage gate, see [AGENTS.md](AGENTS.md#common-commands) — some commands
must go through MCP tools rather than Bash.

## Agent guidance

[AGENTS.md](AGENTS.md) holds the architecture, conventions, and command reference for both humans
and coding agents. `CLAUDE.md` is a symlink to it, so Claude Code reads the same file.

[pub_workspace_link]: https://dart.dev/tools/pub/workspaces
