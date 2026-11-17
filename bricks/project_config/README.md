# project_config

The project-level files each coding agent harness reads to use the VGV plugins.

`vgv_ai install --project` renders this brick into memory and hands each file
to its reconciler, the same way [`user_config`](../user_config/README.md) is
rendered for a user-level install.

## The tree mirrors the repository root

Each top-level folder is one harness and is rendered only when its flag is set.
Inside it, files sit where that harness reads them in a repository, such as
`{{#gemini}}gemini/.gemini/agents/…`. A file at the root of the folder, or
directly inside one of its top-level folders, such as `.claude/settings.json`,
is merged into what is already there. Anything deeper belongs to VGV and is
written whole.

No harness folder holds an instructions file: a project install never writes
the repository's `AGENTS.md`.

| Harness  | Settings                | Agents                      | Commands                   |
| -------- | ----------------------- | --------------------------- | -------------------------- |
| claude   | `.claude/settings.json` |                             |                            |
| gemini   | `.gemini/settings.json` | `.gemini/agents/*.md`       | `.gemini/commands/*.toml`  |
| codex    |                         | `.codex/agents/*.toml`      |                            |
| opencode |                         | `.opencode/agents/*.md`     | `.opencode/commands/*.md`  |
| pi       |                         |                             | `.pi/prompts/*.md`         |
| copilot  |                         | `.github/agents/*.agent.md` |                            |

The skills are not in the brick. The CLI writes one shared copy to
`.agents/skills`, which every harness but Claude Code reads in a project, and
copies the plugin files those skills name to `.vgv_ai/plugins/`.

Gemini's settings only name `AGENTS.md` and `GEMINI.md` as context files, so
Gemini reads the repository's own `AGENTS.md`. Its MCP servers wait for
project-level MCP support.

## Partials

`{{~ agent.md }}` is a symlink to the `user_config` partial, so both bricks
frame an agent the same way from one copy. `mason bundle` follows it.

## Variables

The same as `user_config`'s. See its [README](../user_config/README.md#variables).

## Regenerating the bundle

The bundle is committed and CI fails if it drifts:

```sh
tool/generate_bundles.sh
```
