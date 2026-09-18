# Todo: Plugin resolution pipeline for `install` (issue #24)

Plan: `tasks/plan.md`. Commands assume `cd packages/vgv_ai_cli`.
Focused test: `dart test test/src/<path>`. Full: `dart test`. Analyze: `dart analyze`.

---

## Phase 1: Plugin resolution (fetch + parse)

### Task 1: Resolution models + manifest parsing + deps  ✅
**Description:** Add the CLI-side domain models for plugin resolution and parse
the marketplace manifest. Add the `yaml` and `toml` dependencies.

**Acceptance criteria:**
- [x] `pubspec.yaml` gains `yaml` and `toml` deps; `dart pub get` succeeds.
- [x] `McpServer` (command/args/env/url), `Skill` (name/description/path) and
      `Agent` (name/description) models exist under `lib/src/plugins/models/` with
      `toVars()` serialization matching the shapes the brick pre_gen hook reads.
- [x] `MarketplaceManifest` parses `.claude-plugin/marketplace.json` into a list of
      `{ name, repo }` plugin sources.

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/`
- [ ] Build succeeds: `dart pub get`
- [ ] Manual check: manifest fixture parses into 2 plugin sources.

**Dependencies:** None
**Files likely touched:** `pubspec.yaml`, `lib/src/plugins/*.dart`,
`test/src/plugins/*_test.dart`
**Estimated scope:** M (3-5 files)

### Task 2: `Git` wrapper + `PluginFetcher` (clone marketplace + plugin repos)
**Description:** Add a `Git` wrapper over the `git` executable, modeled on
very_good_cli's `Git` (`lib/src/cli/git_cli.dart`): mockable, with
`reachable(remote)` and `clone(repo, ref, dest)` (shallow, resolving/returning the
commit SHA). Build a `PluginFetcher` on top that clones the marketplace repo and
each plugin source repo into a managed cache dir, returning dir handles + pinned
commits. Provide a fake `PluginFetcher` backed by fixtures for tests.

**Acceptance criteria:**
- [ ] `Git` exposes `reachable` and `clone` and is injectable/mockable; missing
      `git` or an unreachable remote yields a clear, typed error.
- [ ] `PluginFetcher` fetches the marketplace dir and a plugin source dir given its
      `owner/name` slug, returning the resolved commit SHA for each.
- [ ] A fake fetcher backed by local fixture dirs is available to tests (no network).

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: fake fetcher returns fixture dirs + pins without network.

**Dependencies:** Task 1
**Files likely touched:** `lib/src/cli/git_cli.dart`,
`lib/src/plugins/plugin_fetcher.dart`, `test/src/plugins/plugin_fetcher_test.dart`,
`test/fixtures/**`
**Estimated scope:** M

### Task 3: Extractors (`.mcp.json`, `SKILL.md`/agent frontmatter → models)
**Description:** Parse a plugin directory into MCP servers (`.mcp.json` →
`mcpServers`), skills (`skills/*/SKILL.md` frontmatter), and agents
(`agents/**/*.md` frontmatter). Compose a `PluginResolver` that runs the fetcher
over every marketplace plugin and aggregates results.

**Acceptance criteria:**
- [ ] `.mcp.json` parses into `Map<String, McpServer>`, handling both local
      (command/args/env) and remote (url) servers.
- [ ] YAML frontmatter parses into `NamedEntry`; entries missing name/description
      are skipped with a warning, not a crash.
- [ ] `PluginResolver` aggregates MCP servers, skills, and agents across all
      resolved plugins with stable ordering.

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: wingspan + ai-flutter fixtures yield context7/dart/very-good-cli
      servers and the expected skills/agents.

**Dependencies:** Task 1, Task 2
**Files likely touched:** `lib/src/plugins/extractors.dart`,
`lib/src/plugins/plugin_resolver.dart`, `test/src/plugins/*_test.dart`
**Estimated scope:** M

### Checkpoint: Resolution
- [ ] `dart test` green for resolution units
- [ ] Given fixtures, resolver yields expected MCP servers, skills, agents
- [ ] Review before proceeding

---

## Phase 2: Generation + reconciliation

### Task 4: Map resolved data → brick vars and render to staging
**Description:** Build the brick var map from resolved plugins + harness flags +
`skills_root`, then render `agentsBundle` (preGen → generate) into a temp staging
directory. Reuse the render pattern from `agents_bundle_test.dart`.

**Acceptance criteria:**
- [ ] A `StagingGenerator` produces vars (`mcp_servers`, `skills`, `agents`,
      harness booleans, `skills_root`) and renders into a staging dir.
- [ ] Skill entries carry a canonical `path` (see Task 7) so `AGENTS.md` can
      reference the single copy instead of inlining bodies.
- [ ] Only selected-harness files are emitted (matches existing bundle behavior).
- [ ] Rendered JSON/TOML contain the resolved servers/skills/agents.

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/staging_generator_test.dart`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: staging dir mirrors README file map for selected harnesses.

**Dependencies:** Task 3
**Files likely touched:** `lib/src/plugins/staging_generator.dart`,
`test/src/plugins/staging_generator_test.dart`
**Estimated scope:** M

### Task 5: JSON deep-merge reconciler (claude, gemini, opencode, pi)
**Description:** Reconcile staged JSON settings files into their real destinations
via recursive map deep merge, preserving user-owned keys and creating parent dirs
and files when absent.

**Acceptance criteria:**
- [ ] Recursive deep merge: nested maps merge, non-map leaves take the staged
      (VGV) value, keys only present in the user's file are preserved.
- [ ] Missing destination file/dir is created from staging.
- [ ] Reconciler maps each staged JSON file to the destination in the README table.

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/reconciler_test.dart`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: a fixture user `settings.json` keeps its keys and gains VGV keys.

**Dependencies:** Task 4
**Files likely touched:** `lib/src/plugins/reconciler.dart`,
`test/src/plugins/reconciler_test.dart`
**Estimated scope:** M

### Task 6: Codex TOML merge + `AGENTS.md` overwrite reconcilers
**Description:** Extend reconciliation to codex `config.toml` (TOML parse → deep
merge → serialize with `toml`) and to the CLI-managed `AGENTS.md` files (full
overwrite into each harness destination).

**Acceptance criteria:**
- [ ] Codex TOML round-trips: user tables preserved, VGV `mcp_servers` tables added.
- [ ] `AGENTS.md` files overwrite gemini/codex/opencode destinations.
- [ ] Reconciler dispatches per file by format (JSON vs TOML vs markdown).

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/reconciler_test.dart`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: fixture `config.toml` with a user table survives the merge.

**Dependencies:** Task 5
**Files likely touched:** `lib/src/plugins/reconciler.dart`,
`test/src/plugins/reconciler_test.dart`
**Estimated scope:** M

### Task 7: Brick change — `Skill`/`Agent` models (replace `NamedEntry`) + bundle regen
**Description:** Replace the generic `NamedEntry { name, description }` (used for
both skills and agents) with specific `Skill { name, description, path }` and
`Agent { name, description }` models. The `path` lets the `AGENTS.md` harnesses
reference the single canonical skill copy instead of inlining bodies. Update
`pre_gen.dart`, `agents_configuration.dart`, and the `{{~ agents.md }}` partial to
render the skill path, delete `NamedEntry`, regenerate `*.g.dart`, and regenerate
the committed bundle. Brick out-of-scope note is waived for this.

**Acceptance criteria:**
- [ ] `Skill` (name, description, path) and `Agent` (name, description) models exist;
      `NamedEntry` and its test are removed; nothing references it.
- [ ] `agents.md` partial renders each skill's path; omitted/empty path degrades to
      name+description only.
- [ ] Bundle regenerated via `tool/generate_agents_bundle.sh`; CI drift check green.

**Verification:**
- [ ] Tests pass: `cd bricks/agents/hooks && dart test`
- [ ] Build succeeds: `cd bricks/agents/hooks && dart run build_runner build`
- [ ] Manual check: `dart test packages/vgv_ai_cli/test/src/templates/` renders paths.

**Dependencies:** None (can land first; unblocks Task 4's skill `path`)
**Files likely touched:** `bricks/agents/hooks/lib/models/skill/*` (new),
`bricks/agents/hooks/lib/models/agent/*` (new),
`bricks/agents/hooks/lib/models/named_entry/*` (deleted),
`bricks/agents/hooks/lib/models/models.dart`,
`bricks/agents/hooks/lib/models/agents_configuration.dart`,
`bricks/agents/hooks/lib/pre_gen.dart`,
`bricks/agents/hooks/test/models/{skill,agent}_test.dart`,
`bricks/agents/__brick__/{{~ agents.md }}`,
`packages/vgv_ai_cli/lib/src/templates/agents_bundle.dart` (regenerated)
**Estimated scope:** M

### Task 8: Skill materialization into `skills_root` + `skills-lock.json`
**Description:** Copy each resolved plugin's `skills/*` **once** into
`<skills_root>/<plugin>/<skill>/` (the shared "partial"), build the normalized
skill model (name, description, canonical path, normalized frontmatter) that feeds
the per-harness adapters, and write `<skills_root>/skills-lock.json` recording each
skill's remote origin (`repo`, `ref`, resolved `commit`, source `path`) and target.
Copy (not symlink). Only manage paths recorded in the lock so user-authored skills
are never touched.

**Acceptance criteria:**
- [ ] Skills copy once into `<skills_root>/<plugin>/...`; unmanaged dirs untouched.
- [ ] Normalized skill model exposes the canonical path consumed by Task 4's vars.
- [ ] `skills-lock.json` matches the shape in `tasks/plan.md` (version, skillsRoot,
      per-plugin repo/ref/commit/skills[]); re-running is idempotent.

**Verification:**
- [ ] Tests pass: `dart test test/src/plugins/skills_installer_test.dart`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: fixtures produce expected files + lock; user skill preserved.

**Dependencies:** Task 3 (resolved skills + pinned commits from Task 2)
**Files likely touched:** `lib/src/plugins/skills_installer.dart`,
`lib/src/plugins/skills_lock.dart`,
`test/src/plugins/skills_installer_test.dart`
**Estimated scope:** M

### Checkpoint: Generation
- [ ] Staging dir contains only selected harness files
- [ ] Merging into a fixture real config preserves user keys and adds VGV keys
- [ ] Skills materialize under `skills_root`; `skills-lock.json` pins their origin
- [ ] Review before proceeding

---

## Phase 3: Command + polish

### Task 9: `install` command wiring
**Description:** Add `InstallCommand` orchestrating resolve → generate → reconcile
→ materialize. Expose harness flags (`--claude/--gemini/--codex/--opencode/--pi`),
`--skills-root`, and `--update` (refresh pinned commits), with progress logging and
actionable errors. Register it in `command_runner.dart`.

**Acceptance criteria:**
- [ ] `vgv_ai install` runs the full pipeline; at least one harness required.
- [ ] Flags select harnesses, override skills root, and `--update` refreshes pins
      (default respects `skills-lock.json`); `--help` documents them.
- [ ] Failures (no git, fetch error, no harness) return non-zero with clear messages.

**Verification:**
- [ ] Tests pass: `dart test test/src/commands/install_command_test.dart`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: `dart run bin/vgv_ai.dart install --help`.

**Dependencies:** Tasks 6, 7, 8
**Files likely touched:** `lib/src/commands/install_command.dart`,
`lib/src/commands/commands.dart`, `lib/src/command_runner.dart`,
`test/src/commands/install_command_test.dart`
**Estimated scope:** M

### Task 10: End-to-end install test + docs
**Description:** Add an end-to-end test that runs `install` against a fake fetcher
and a temp HOME, asserting real config destinations are written/merged correctly
and skills materialize with a valid `skills-lock.json`. Update README(s) to
document the `install` command.

**Acceptance criteria:**
- [ ] E2E test: install with fixtures writes/merges every selected destination and
      materializes skills + lockfile.
- [ ] `packages/vgv_ai_cli/README.md` documents `install` usage, flags, and the
      `skills-lock.json`.
- [ ] Note resolved decisions (materialization, resolve-all, Git wrapper) in docs.

**Verification:**
- [ ] Tests pass: `dart test`
- [ ] Build succeeds: `dart analyze`
- [ ] Manual check: coverage of new code is meaningful.

**Dependencies:** Task 9
**Files likely touched:** `test/src/commands/install_command_test.dart`,
`packages/vgv_ai_cli/README.md`
**Estimated scope:** M

### Checkpoint: Complete
- [ ] Skills materialize with a valid `skills-lock.json`
- [ ] `dart test` and `dart analyze` clean in `packages/vgv_ai_cli`
- [ ] `install --help` documents flags; happy path runs against fixtures
- [ ] Ready for review
