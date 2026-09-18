# Implementation Plan: Plugin resolution pipeline for the `install` command

Tracks GitHub issue [#24](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/24).

## Overview

The `agents` brick already translates MCP servers and remote skills/agents into
every harness's config dialect (`GeminiSettings.fromServers`,
`OpenCodeConfig.fromServers`, `CodexConfig.fromServers`, `PiSettings`, the shared
`AGENTS.md` partial, plus the Claude marketplace settings). What is missing is
the CLI pipeline that **populates** the `mcp_servers`, `skills`, and `agents`
brick vars from the real VGV Claude plugins.

This plan adds an `install` command to `packages/vgv_ai_cli` that:

1. Reads the enabled VGV plugins from the Very Good Claude marketplace
   (`VeryGoodOpenSource/very_good_claude_marketplace`).
2. Fetches each plugin's source repo and extracts its MCP servers
   (`.mcp.json`), skills (`skills/*/SKILL.md`), and agents (`agents/**/*.md`).
3. Maps them onto the brick's `mcp_servers` / `skills` / `agents` vars.
4. Renders the bundled `agents` brick into a per-harness staging directory.
5. Reconciles staging output against the user's real config with a deep merge so
   user-owned keys are preserved.

## Discovered facts (source of truth for implementation)

- **Marketplace manifest:** `.claude-plugin/marketplace.json` in
  `VeryGoodOpenSource/very_good_claude_marketplace`. Its `plugins[]` entries
  carry `name` and `source: { source: "github", repo: "owner/name" }`. The two
  enabled plugins today are `vgv-wingspan` and `vgv-ai-flutter-plugin`.
- **Each plugin repo** (e.g. `VeryGoodOpenSource/vgv-wingspan`) contains:
  - `.claude-plugin/plugin.json` — metadata (`name`, `version`).
  - `.mcp.json` — `{ "mcpServers": { name: { command, args, env } | { url } } }`.
  - `skills/*/SKILL.md` — YAML frontmatter with `name` and `description`.
  - `agents/**/*.md` — YAML frontmatter with `name` and `description`.
- **Brick vars the pre_gen hook reads** (`bricks/agents/hooks/lib/pre_gen.dart`):
  - `mcp_servers`: `Map<String, {command, args, env, url}>`.
  - `skills` / `agents`: `List<{name, description}>`.
  - `skills_root`: canonical skills path (already a brick var, defaults
    `~/.agents/skills`).
  - `claude`/`gemini`/`codex`/`opencode`/`pi`: harness selection booleans.
- **Harnesses load skills from files on disk, not from metadata.** Per the pi
  skills spec (and mirrored by the other harnesses), skills are discovered by
  scanning `skills_root` (`~/.agents/skills/` by default) for `SKILL.md` files.
  The `AGENTS.md` partial only lists name+description for progressive disclosure;
  for a skill body to actually load, its files must exist under `skills_root`.
  Therefore the CLI must **materialize** each plugin's `skills/*` into
  `skills_root` — the brick vars alone are not sufficient. There is no native
  "remote skill" fetch in any harness.
- **Rendering:** the brick is shipped as `agentsBundle`
  (`packages/vgv_ai_cli/lib/src/templates/agents_bundle.dart`). It is rendered
  with `MasonGenerator.fromBundle(agentsBundle)` → `hooks.preGen` →
  `generate(DirectoryGeneratorTarget(...))`, exactly as the existing
  `test/src/templates/agents_bundle_test.dart` does.
- **Staging → real config mapping** (from `bricks/agents/README.md`):

  | staging file             | real destination                   | format |
  | ------------------------ | ---------------------------------- | ------ |
  | `claude/settings.json`   | `~/.claude/settings.json`          | JSON   |
  | `gemini/settings.json`   | `~/.gemini/settings.json`          | JSON   |
  | `gemini/AGENTS.md`       | `~/.gemini/AGENTS.md`              | md     |
  | `codex/config.toml`      | `~/.codex/config.toml`             | TOML   |
  | `codex/AGENTS.md`        | `~/.codex/AGENTS.md`              | md     |
  | `opencode/opencode.json` | `~/.config/opencode/opencode.json` | JSON   |
  | `opencode/AGENTS.md`     | `~/.config/opencode/AGENTS.md`     | md     |
  | `pi/settings.json`       | `~/.pi/agent/settings.json`        | JSON   |

## Architecture Decisions

- **Fetch strategy: `git clone` behind a `Git` wrapper.** The marketplace
  points each plugin at a GitHub repo; skills/agents live in directories whose
  contents we cannot list over raw HTTP without the GitHub API. A clone into a
  managed cache dir gives us the full tree, mirroring how Claude Code resolves the
  marketplace. We model a `Git` wrapper in the spirit of very_good_cli's `Git`
  (`lib/src/cli/git_cli.dart`): a thin, mockable abstraction over the
  `git` executable exposing `reachable(remote)` and `clone(repo, ref, dest)`
  (shallow, pinned to a resolved commit). A `PluginFetcher` sits on top and is
  faked in tests to point at local fixture directories — tests never hit the
  network.
- **CLI-side domain models, not shared with the brick hooks.** The brick hooks
  package (`bricks/agents/hooks`) is not a dependency of the CLI. The CLI builds
  plain `Map`/`List` vars that the pre_gen hook re-parses. The CLI keeps its own
  small `McpServer` / `NamedEntry` / manifest models and serializes them to the
  var shapes the hook expects. This keeps the bundle boundary clean.
- **Skills are materialized once, then referenced (the "partial" model).** Each
  skill is copied a single time into `skills_root`, namespaced under
  `<skills_root>/<plugin>/<skill>/`. That single copy is the shared source — the
  "partial". No harness re-embeds skill bodies; every harness references the one
  copy in the form it understands:
  - **pi** already points `skills: [skills_root]` at the directory and loads the
    files natively.
  - **gemini / codex / opencode** only ingest skills through their instructions
    file, so their `AGENTS.md` lists each skill by name, description, and its
    **canonical path**, letting the agent read the body on demand (progressive
    disclosure) instead of inlining it.
  - **claude** resolves skills itself from the marketplace and needs no copy.
  A normalized skill model (name, description, canonical path, normalized
  frontmatter) feeds per-harness adapters, so differences in frontmatter and
  output format (markdown vs JSON vs TOML) are absorbed in one place rather than
  duplicated per harness.
- **Copy, not symlink.** Cross-platform safe and self-contained; the lockfile,
  not the filesystem, tracks which paths are managed. Symlink stays a possible
  later optimization.
- **Materialization is pinned via `skills-lock.json` ("linked as remote").**
  `install` checks out each plugin at a resolved commit and records each skill's
  remote origin (`repo`, `ref`, resolved `commit`, source `path`) and its target
  under `skills_root`. The lockfile is the "link": installs are reproducible and
  provenance is explicit without re-resolving the marketplace. **Pinned by
  default** — a re-run reuses the locked commit; refreshing to newer commits
  requires an explicit `--update` flag. The lock lives next to the skills at
  `<skills_root>/skills-lock.json`.
- **Brick change: replace generic `NamedEntry` with specific `Skill`/`Agent`
  models.** `NamedEntry { name, description }` currently backs both skills and
  agents in the hooks. Skills now need a `path` (to reference the canonical copy),
  so the generic model no longer fits. Introduce `Skill { name, description, path }`
  and `Agent { name, description }`, delete `NamedEntry`, update `pre_gen.dart`,
  `agents_configuration.dart`, and the `agents.md` partial (render the skill path),
  then regenerate `*.g.dart` and the committed bundle. The issue's "brick out of
  scope" note is explicitly waived for this.
- **Agents stay listing-only.** No non-Claude harness loads agent `.md` bodies
  from disk today, so agents are surfaced through the `AGENTS.md` listing only; a
  follow-up `vgv_ai_cli init` command may later add project `AGENTS.md`/`CLAUDE.md`
  files.
- **Resolve every plugin listed in the marketplace manifest.** No user-facing
  subset selection; adding a plugin to `marketplace.json` is enough for the CLI to
  pick it up.
- **Reconciliation is per-file by format.** JSON files deep merge (recursive map
  merge, brick values win on leaf conflicts for VGV-owned keys, user keys
  preserved). TOML (codex) parse → deep merge → re-serialize with the `toml`
  package. `AGENTS.md` files are fully managed by the CLI and overwritten.
- **New dependencies:** `yaml` (frontmatter parsing) and `toml` (codex merge) in
  `packages/vgv_ai_cli/pubspec.yaml`. `mason` is already present.
- **Enabled-plugin set stays the source of truth in the marketplace manifest.**
  The CLI resolves every plugin listed in `marketplace.json` rather than
  hardcoding names, so adding a plugin to the marketplace is enough.

## Task List

### Phase 1: Plugin resolution (fetch + parse)
- [ ] Task 1: Resolution models + manifest parsing + deps
- [ ] Task 2: `Git` wrapper + `PluginFetcher` (clone marketplace + plugin repos)
- [x] Task 3: Extractors (`.mcp.json`, `SKILL.md`/agent frontmatter → models)

### Checkpoint: Resolution
- [x] `dart test` green for resolution units
- [x] Given local fixtures, resolver yields expected MCP servers, skills, agents

### Phase 2: Generation + reconciliation
- [ ] Task 4: Map resolved data → brick vars and render `agentsBundle` to staging
- [ ] Task 5: JSON deep-merge reconciler (claude, gemini, opencode, pi)
- [ ] Task 6: Codex TOML merge + `AGENTS.md` overwrite reconcilers
- [ ] Task 7: Brick change — `Skill`/`Agent` models (replace `NamedEntry`) + bundle regen
- [ ] Task 8: Skill materialization into `skills_root` + `skills-lock.json`

### Checkpoint: Generation
- [ ] Staging dir contains only selected harness files
- [ ] Merging into a fixture "real config" preserves user keys and adds VGV keys
- [ ] Skills copy once under `skills_root`; `AGENTS.md` references their paths
- [ ] `skills-lock.json` pins each skill's origin

### Phase 3: Command + polish
- [ ] Task 9: `install` command wiring (flags incl. `--update`, orchestration, errors)
- [ ] Task 10: End-to-end install test + README/docs update

### Checkpoint: Complete
- [ ] `dart test` and `dart analyze` clean in `packages/vgv_ai_cli`
- [ ] `install --help` documents flags; happy path runs against fixtures
- [ ] Ready for review

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| `git` not installed on user machine | High | Detect `git` up front; clear error. Consider GitHub-API/HTTP fallback later. |
| TOML deep merge loses formatting/comments | Med | Codex config is CLI-managed; acceptable to re-serialize. Cover with round-trip test. |
| Network flakiness during clone | Med | Shallow clone, surface actionable error, keep `PluginFetcher` mockable so tests never hit the network. |
| Plugin frontmatter missing `name`/`description` | Med | Skip entry with a warning rather than failing the whole install. |
| Deep merge clobbers user MCP servers with same key | Low | Merge maps recursively; on key collision document that VGV-owned keys win, others preserved. |
| Materialized skills clobber user-authored files in `skills_root` | Med | Namespace under `<skills_root>/<plugin>/...`; only manage paths recorded in `skills-lock.json`, never touch unmanaged dirs. |
| Symlinks break on Windows | Low | Default to copy; treat symlink as an opt-in optimization. |

## Resolved decisions (from review)
- **Skill materialization:** copy each skill once into `skills_root` as the shared
  "partial"; every harness references that single copy (pi via directory, others
  via canonical path in `AGENTS.md`). A normalized skill model + per-harness
  adapters absorb frontmatter/format differences. Tasks 7 (brick) & 8 (CLI).
- **Copy vs symlink:** copy.
- **Re-run semantics:** pinned by default; `--update` refreshes to newer commits.
- **Agents on disk:** listing-only for now; project `AGENTS.md`/`CLAUDE.md` files
  deferred to a follow-up `vgv_ai_cli init` command (open a separate issue).
- **Brick models:** replace generic `NamedEntry` with specific `Skill`/`Agent`
  models; brick change is in scope for this issue.
- **Lockfile:** `<skills_root>/skills-lock.json`, `version: 1` shape below.
- **Uninstall:** out of scope (open a follow-up issue if needed).
- **Plugin selection:** resolve every plugin in the marketplace manifest.
- **Fetch:** `git clone` behind a very_good_cli-style `Git` wrapper (Task 2).

## Open Questions
- None outstanding.

## Follow-up issues to open
- `vgv_ai_cli init`: scaffold project `AGENTS.md` / `CLAUDE.md` files.
- `vgv_ai_cli uninstall`: remove VGV-managed keys + materialized skills using the
  lockfile.

## `skills-lock.json` (proposed shape)
```json
{
  "version": 1,
  "skillsRoot": "~/.agents/skills",
  "plugins": {
    "vgv-wingspan": {
      "repo": "VeryGoodOpenSource/vgv-wingspan",
      "ref": "main",
      "commit": "<resolved-sha>",
      "skills": [
        { "name": "plan", "path": "skills/plan", "target": "vgv-wingspan/plan" }
      ]
    }
  }
}
```
