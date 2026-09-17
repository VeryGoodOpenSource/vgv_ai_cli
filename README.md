# vgv_ai_cli

A CLI that configures Very Good AI coding agents and tooling.

This is a [pub workspace][pub_workspace_link] monorepo. The CLI lives in
[`packages/vgv_ai_cli`](packages/vgv_ai_cli) — see its README for installation and usage.

## Contributor setup

This repo ships a committed Claude Code configuration in `.claude/settings.json`. It declares
the `very-good-claude-code-marketplace` and enables two plugins: **vgv-wingspan** (planning and
review workflows) and **vgv-ai-flutter-plugin** (Dart quality gates and hooks).

### 1. Install the prerequisites

| Tool | Version |
|---|---|
| Dart SDK | `^3.13.0` |
| Very Good CLI | `^1.5.0` — `dart pub global activate very_good_cli "^1.5.0"` |
| `jq` | any |
| `gh` | authenticated, with access to this org |

The Dart version matters more than it looks. On 3.12 the plugin's analyze hook reports errors
against this codebase's Dart 3.13 syntax, and those errors read as real ones.

### 2. Trust the folder

Open the repo in Claude Code and accept the trust prompt. The marketplace resolves from the
committed settings — you do **not** need to run `/plugin marketplace add`.

### 3. Confirm the plugins installed, then restart

Run `/plugin` and check that both plugins show as enabled. Then restart the session: settings
apply immediately, but hooks and MCP servers only bind at session start.

This step is not optional bookkeeping. Wingspan normally nudges you when a companion plugin is
missing, but it decides "already installed" by looking for the plugin name in
`.claude/settings.json` — which this repo commits. If your install silently failed, nothing will
tell you, and Claude will carry on without the hooks or quality gates.

### Verifying

```bash
dart pub get && dart analyze --fatal-infos --fatal-warnings lib test
```

Run that from `packages/vgv_ai_cli`. For the full test and coverage gate, see
[CLAUDE.md](CLAUDE.md) — some commands must go through MCP tools rather than Bash.

[pub_workspace_link]: https://dart.dev/tools/pub/workspaces
