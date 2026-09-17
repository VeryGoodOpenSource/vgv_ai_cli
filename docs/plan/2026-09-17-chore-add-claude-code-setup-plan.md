---
title: "chore: add committed Claude Code setup"
type: chore
date: 2026-09-17
---

## chore: add committed Claude Code setup - Standard

## Overview

Add a committed `.claude/settings.json` to `vgv_ai_cli` so every contributor shares one Claude Code configuration built on `vgv-wingspan` (lifecycle workflows) and `vgv-ai-flutter-plugin` (Dart quality gates, MCP tools, hooks). Correct `CLAUDE.md` so its documented commands match what the plugin hooks actually permit. Add a contributor setup section to the README. Branch protection on `main` is deliberately **deferred** to a follow-up; see Technical Considerations for why enabling it alongside this PR would deadlock it.

Configuration only. No custom hooks, no repo-local skills.

Derived from [the brainstorm](../brainstorm/2026-09-17-claude-code-setup-brainstorm-doc.md).

## Problem Statement / Motivation

`CLAUDE.md` currently documents `dart test test/...` and `dart test --plain-name '...'` as the way to run tests. The flutter plugin ships a `PreToolUse` hook (`block-cli-workarounds.sh`) that **denies** `dart test`, `very_good test`, and `flutter test` when invoked through Bash. Both documented commands fail the moment the plugin is active, and the `very_good_cli` MCP tool offered as the replacement accepts no file path and no name filter, so it cannot run a single test at all.

Beyond that, nothing about the current setup is reproducible. Plugins are installed at user scope on one machine, the VGV marketplace resolves there from a local directory path that no teammate has, and a contributor cloning this repo gets none of it with no indication anything is missing.

Separately, the setup is meant to run unattended. Wingspan's `/build` is designed to implement, validate, commit, push, and open a PR in one pass, and that only works if the routine steps are pre-approved. Without an allow list, an unattended build stops at a prompt partway through and the autonomy is theoretical. The allow list below is that decision made explicit, and it is why the deny list exists at all.

Two findings raise the stakes. First, the flutter plugin runs `dart analyze` on every `.dart` edit and feeds failures back to Claude as work to do. On a toolchain below Dart 3.13 that output includes `This requires the experimental 'primary-constructors' language feature`, aimed squarely at the `new({required this._logger})` convention this repo uses — so Claude is invited to rewrite correct 3.13 syntax into broken 3.12 syntax on every edit, silently. Second, the plugin's own minimum `very_good_cli` version is `1.3.0` while this repo needs `^1.5.0` for pub workspace coverage, so the plugin's version warning stays quiet and the run dies later inside the coverage step.

## Proposed Solution

### 1. `.claude/settings.json` (new, committed)

```json
{
  "extraKnownMarketplaces": {
    "very-good-claude-code-marketplace": {
      "source": {
        "source": "github",
        "repo": "VeryGoodOpenSource/very-good-claude-code-marketplace",
        "ref": "842e9458e156ac775972cf725c9570b54d7a288b"
      }
    }
  },
  "enabledPlugins": {
    "vgv-wingspan@very-good-claude-code-marketplace": true,
    "vgv-ai-flutter-plugin@very-good-claude-code-marketplace": true
  },
  "permissions": {
    "deny": [
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(git push origin main*)",
      "Bash(git push origin +*)"
    ],
    "allow": [
      "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)", "Bash(git show*)",
      "Bash(git add *)", "Bash(git commit *)", "Bash(git checkout -b *)",
      "Bash(git push*)",
      "Bash(gh pr create*)", "Bash(gh pr view*)", "Bash(gh run list*)",
      "Bash(dart pub get*)", "Bash(dart analyze*)", "Bash(dart format*)",
      "Bash(dart run test*)", "Bash(dart run build_runner *)",
      "Bash(dart run bin/vgv_ai.dart*)",
      "mcp__plugin_vgv-ai-flutter-plugin_dart__*",
      "mcp__plugin_vgv-wingspan_context7__*"
    ]
  }
}
```

Notes on each block:

- **`extraKnownMarketplaces`** is what makes this reproducible. A teammate who trusts the repo folder resolves the marketplace without running `/plugin marketplace add`. The canonical repo name is the **hyphen** form; the underscore form in the flutter plugin's recommendation file works only via GitHub's rename redirect.
- **`ref`** pins the marketplace catalog to a commit. No tags or releases exist on that repo, so a SHA is the only option. See Risks for what this does and does not buy.
- **`enabledPlugins`** is an object of booleans, not an array. It cannot pin versions and cannot install a plugin the user has not resolved.
- **`permissions.deny`** is listed before allow for readability only; deny wins regardless of order or specificity, including across settings scopes.
- **MCP rules** use the plugin-qualified server names observed in-session. The `very-good-cli` server is deliberately absent: the plugin's `check-vgv-cli.sh` hook already auto-approves every call to it, so an allow rule there is dead weight.

### 2. `AGENTS.md` (renamed from `CLAUDE.md`, with corrections)

Adopt the `AGENTS.md` convention used by [very_good_cli](https://github.com/VeryGoodOpenSource/very_good_cli/blob/main/AGENTS.md): `AGENTS.md` is the real file and `CLAUDE.md` is a symlink to it, so Claude Code and any other agent reading `AGENTS.md` share one source. Structure follows that file — VGV philosophy preamble, Project Overview, a single Common Commands block, Architecture, Code Conventions.

Corrections applied in the same pass:

- Replace both `dart test` invocations with `dart run test`. This is not a workaround: the guard matches on the first two tokens being `dart test`, and this repo's own CI already uses `dart run test --run-skipped -t version-verify`.
- State that the full coverage run goes through the `very_good_cli` MCP `test` tool, and that single-test runs go through `dart run test` because the MCP tool has no path or name filter.
- Add a prerequisites block: Dart SDK `^3.13.0`, `very_good_cli ^1.5.0`, `jq`, authenticated `gh` with org access. Include the exact symptom strings for the two silent failures (`experiment_not_enabled_off_by_default` and `Invalid kernel binary format version`).
- Note that the plugin auto-runs `dart analyze` and `dart format` on every `.dart` write.
- Name the five plugin skills that apply to a pure Dart CLI — `green-gate`, `testing`, `license-compliance`, `very-good-analysis-upgrade`, `dart-flutter-sdk-upgrade` — and say the Flutter-only ones do not.
- Record the plugin versions this setup was validated against.

### 3. `.gitignore`

Ignore Wingspan's ephemeral output directories, keep the durable ones tracked:

```gitignore
# Claude Code: personal overrides and local worktrees
.claude/settings.local.json
.claude/worktrees/

# Wingspan ephemeral output
docs/reviews/
docs/code-review/
docs/hotfix-review/
docs/debriefs/
```

The `.claude/` entries matter because committing `settings.json` makes `.claude/` a tracked directory for the first time. This repo actively uses `.claude/worktrees/`, so without these two lines every contributor sees worktree noise in `git status` and personal overrides eventually get committed by accident.

`docs/plan/` and `docs/brainstorm/` stay **tracked**, which deviates from Wingspan's own `.gitignore`. That is deliberate: they are the durable record of why this setup looks the way it does, and a contributor should be able to read that reasoning from the repo. The cost is that they are spell-checked forever, which is why the word list in step 6 matters.

Do **not** create empty `docs/` directories with `.gitkeep`. Git does not track empty directories, and a `.gitkeep` inside an ignored path needs an explicit negation to survive. The skills create these on first write.

### 4. `README.md` contributor setup

A short section covering: trust the folder, run `/plugin` and confirm both plugins show enabled, restart the session so hooks and MCP servers bind, and the prerequisite list. This step exists because committing `.claude/settings.json` **silences Wingspan's own plugin-recommendation hook** — that hook decides "already installed" by grepping this file for the plugin name, so a contributor whose install failed gets no plugins and no nudge.

### 5. Branch protection on `main` — deferred, follow-up issue

`main` currently has no protection. It is the only real control behind the deny list, but enabling it now would block this PR (see Technical Considerations). File a follow-up that resolves the CI path-filter question first, then enables protection. Until it lands, the deny list is a guardrail against accident with nothing behind it, and this plan says so rather than implying otherwise.

### 6. `.github/cspell.json` word list

Add `worktree` and `worktrees` to the `words` array, which is currently empty. Those are the genuine domain terms — this repo uses git worktrees — and they are what a run of the repo's own cspell config over the new markdown actually reports. `CLAUDE.md` is already clean. Verify with the command in the success criteria rather than guessing; the first attempt at this list guessed three words, none of which were real offenders. This is defensive: the spell-check job does not run on this PR, but it lints all markdown on the next PR that touches `lib/`, and a failure there would be confusing and unrelated to that PR's author.

## Technical Considerations

**Permission rules are not a security boundary.** A deny on `Bash(git push --force *)` does not stop `git -C . push --force` or `/usr/bin/git push --force`. (A leading env assignment like `FOO=1 git push --force` *is* caught — deny rules match past those.) The same class of gap exists in the plugin's own Bash guard, which any prefix token defeats (`timeout 30 dart test`). Both are guardrails against accident, not intent. The only real control is server-side branch protection, and this plan defers it — so the deny list ships as a speed bump and nothing more. That is a known, accepted gap, not an oversight.

**Branch protection and the path-filtered workflow can deadlock this very PR.** All four CI jobs live inside `.github/workflows/vgv_ai_cli.yaml`, whose `pull_request.paths` covers only that workflow file, `lib/**`, `test/**`, and `pubspec.yaml`. A config-only PR triggers none of them, so zero checks report. If branch protection is enabled with any *required* status check, this PR — and every future docs or config PR — blocks forever. Enable protection with no required checks, or move `semantic-pull-request` into its own unfiltered workflow first. This must be decided before protection is turned on, not after.

**MCP servers bind their binary at session start.** Upgrading `very_good_cli` mid-session does not affect the running MCP server — verified during planning, where the server kept invoking 1.3.0 after 1.5.0 was activated. Any prerequisite fix requires a session restart.

**No application code changes**, so the `vgv_ai_cli` workflow — which triggers only on `lib/**`, `test/**`, `pubspec.yaml`, and its own file — does not run on this PR. That has a consequence worth knowing: the `spell-check` job is configured with `modified_files_only: false`, so it lints **every** markdown file in the repo whenever it does run. The docs this plan adds will therefore first be spell-checked by some later PR that touches `lib/`, not by this one.

**Security.** The settings file grants push and `gh pr create` without a prompt to anyone who trusts the folder. That is the intended trade, bounded for now only by the repo being private, until the branch-protection follow-up lands.

## Implementation Phases

Small enough for one PR. `/build` runs it as a single phase.

Suggested order, because later steps depend on earlier ones being verifiable:

1. `.claude/settings.json`
2. `CLAUDE.md` corrections
3. `.gitignore` + `README.md`

One addition surfaced while writing criteria: the repo root has **no `README.md`** (only `packages/vgv_ai_cli/README.md`). Contributor setup belongs at the root next to `.claude/`, so this plan creates one.

## Success Criteria

```success-criteria
GOAL: A contributor who clones vgv_ai_cli and trusts the folder gets the same Claude Code setup as everyone else, with documented commands that actually run and a server-side guardrail on main.

SUCCESS CRITERIA:
- .claude/settings.json is valid JSON | verify: jq empty .claude/settings.json
- Both plugins are enabled under their exact marketplace-qualified identifiers | verify: jq -e '.enabledPlugins["vgv-wingspan@very-good-claude-code-marketplace"] == true and .enabledPlugins["vgv-ai-flutter-plugin@very-good-claude-code-marketplace"] == true' .claude/settings.json
- The marketplace is declared with the canonical hyphen repo name and pinned to a 40-char commit SHA | verify: jq -e '.extraKnownMarketplaces["very-good-claude-code-marketplace"].source.repo == "VeryGoodOpenSource/very-good-claude-code-marketplace" and (.extraKnownMarketplaces["very-good-claude-code-marketplace"].source.ref | length) == 40' .claude/settings.json
- The deny list covers force-push and pushes to main | verify: jq -e '(.permissions.deny | map(select(test("--force|-f "))) | length) >= 1 and (.permissions.deny | map(select(test("main"))) | length) >= 1' .claude/settings.json
- No MCP allow rule is an unanchored glob, which Claude Code skips with a warning | verify: jq -e '[.permissions.allow[] | select(test("^mcp__")) | select(test("^mcp__[a-zA-Z0-9_-]+(__|$)") | not)] | length == 0' .claude/settings.json
- AGENTS.md no longer presents a hook-blocked test command as runnable | verify: ! grep -qE '^\s*(dart|flutter) test' AGENTS.md
- AGENTS.md documents the single-test path that actually works | verify: grep -q 'dart run test' AGENTS.md
- Wingspan ephemeral output is ignored while durable artifacts stay tracked | verify: git check-ignore -q docs/reviews/ && git check-ignore -q docs/code-review/ && git check-ignore -q docs/hotfix-review/ && ! git check-ignore -q docs/plan/
- CLAUDE.md is a symlink to AGENTS.md so both agent conventions resolve to one file | verify: test -L CLAUDE.md && [ "$(readlink CLAUDE.md)" = "AGENTS.md" ]
- A root README documents contributor setup including marketplace resolution | verify: test -f README.md && grep -q 'very-good-claude-code-marketplace' README.md
- Spell check passes over all markdown, which is what CI eventually runs | verify: npx -y cspell@8 --config .github/cspell.json --no-progress "**/*.md"
- Claude Code local overrides and worktrees cannot be committed by accident | verify: git check-ignore -q .claude/settings.local.json && git check-ignore -q .claude/worktrees/
- The repo's own quality gates still pass on the required toolchain | verify: (cd packages/vgv_ai_cli && dart pub get && dart analyze --fatal-infos --fatal-warnings lib test && dart format --set-exit-if-changed .)
- The coverage gate passes through the MCP tool on very_good_cli 1.5.0 | verify: manual 1. Restart the Claude session so the MCP server rebinds to very_good_cli 1.5.0. 2. Call the very-good-cli MCP test tool with directory=packages/vgv_ai_cli, dart=true, coverage=true, min_coverage=100, check_ignore=true. 3. Confirm it reports 100% coverage and does not fail with "Directory listing failed, path = './coverage/'".
- A contributor on a clean config resolves the marketplace from the trust prompt alone | verify: manual 1. Set CLAUDE_CONFIG_DIR to an empty temp dir. 2. Open the repo in Claude Code and accept the trust prompt. 3. Run /plugin and confirm both plugins appear and are enabled. 4. Confirm no manual "/plugin marketplace add" was needed.

NON-GOALS:
- Custom hooks, including a guard on the generated lib/src/version.dart (deferred in the brainstorm)
- Repo-local skills for release or command scaffolding
- Committing .tool-versions or otherwise pinning the toolchain in-repo
- Designing what the vgv_ai CLI will scaffold into other projects
- Fixing the upstream plugin gaps this plan documents
- Enabling branch protection on main (deferred to a follow-up that must first resolve the CI path-filter deadlock)

VERIFICATION COMMAND: jq empty .claude/settings.json && jq -e '.enabledPlugins["vgv-wingspan@very-good-claude-code-marketplace"] == true and .enabledPlugins["vgv-ai-flutter-plugin@very-good-claude-code-marketplace"] == true' .claude/settings.json && jq -e '.extraKnownMarketplaces["very-good-claude-code-marketplace"].source.repo == "VeryGoodOpenSource/very-good-claude-code-marketplace" and (.extraKnownMarketplaces["very-good-claude-code-marketplace"].source.ref | length) == 40' .claude/settings.json && jq -e '(.permissions.deny | map(select(test("--force|-f "))) | length) >= 1 and (.permissions.deny | map(select(test("main"))) | length) >= 1' .claude/settings.json && ! grep -qE '^\s*(dart|flutter) test' AGENTS.md && grep -q 'dart run test' AGENTS.md && test -L CLAUDE.md && [ "$(readlink CLAUDE.md)" = "AGENTS.md" ] && git check-ignore -q docs/reviews/ && git check-ignore -q docs/code-review/ && git check-ignore -q docs/hotfix-review/ && ! git check-ignore -q docs/plan/ && test -f README.md && grep -q 'very-good-claude-code-marketplace' README.md && npx -y cspell@8 --config .github/cspell.json --no-progress "**/*.md" && git check-ignore -q .claude/settings.local.json && git check-ignore -q .claude/worktrees/ && (cd packages/vgv_ai_cli && dart pub get && dart analyze --fatal-infos --fatal-warnings lib test && dart format --set-exit-if-changed .)
```

## Success Metrics

- A contributor reaches a first productive command without asking anyone how to set up Claude.
- No session produces a `dart test` permission denial, because nothing documented tells anyone to run it.
- No PR contains Dart 3.12-shaped syntax regressions introduced by the analyze hook.

## Dependencies & Risks

**The marketplace `ref` pin is partial, and the plan should not oversell it.** The pinned SHA freezes the catalog, and that catalog lists `vgv-wingspan 0.0.5` and `vgv-ai-flutter-plugin 0.0.5`. But each plugin entry sources from its own GitHub repo with **no `ref` of its own**, so what actually installs still tracks those repos' default branches. Two contributors on this same commit can still end up running different hook behavior. The durable fix is upstream: pin refs in the marketplace manifest. File that as a follow-up.

**Switching to the GitHub marketplace is itself a version move.** The local directory-source copy on the author's machine carries `vgv-wingspan 0.0.4`; public `main` carries `0.0.5`. This plan was researched against 0.0.4 behavior. Re-confirm the hook scripts have not changed after switching.

**The author's machine cannot validate the contributor path.** `~/.claude/plugins/known_marketplaces.json` registers `very-good-claude-code-marketplace` as a `directory` source pointing at a local worktree. The committed entry uses the same key with a `github` source. Validating the clean-clone flow requires an empty `CLAUDE_CONFIG_DIR`, and anyone holding the directory source must remove it — document that.

**The deny list ships without enforcement behind it.** Branch protection is deferred, so until the follow-up lands nothing server-side stops a force-push to `main`. Accepted knowingly.

**`jq` fails in two directions.** `block-cli-workarounds.sh` and `check-vgv-cli.sh` `exit 1` without it, so the guards fail open and emit hook errors. `analyze.sh` and `format.sh` `exit 0`, so the quality gates disappear silently. Only the prerequisites doc catches this.

**Plugins install after the trust prompt.** Settings apply immediately; hooks and MCP servers do not. The first session can run without them, which is why the README says to restart.

**`context7`** (Wingspan research skills) needs `npx` and network access, and surfaces as a server-connect failure at session start.

**No CI job runs on this PR at all.** All four jobs — `build`, `spell-check`, `verify-version`, `semantic-pull-request` — live inside the path-filtered `vgv_ai_cli` workflow, which this config-only change does not trigger. So the conventional-title check is unenforced here, and the new markdown reaches `main` unchecked. See Technical Considerations for why that collides with branch protection.

**The spell check could not be verified locally.** `cspell` 10.x requires Node `>=22.18.0`; this machine has `22.13.1`, so the run aborted before checking anything. The word list in step 6 is therefore a best guess. Either upgrade Node and run `npx cspell --config .github/cspell.json "**/*.md"` before merging, or accept that the first `lib/`-touching PR after this one may surface spelling failures in these docs.

**Toolchain state at planning time.** The author's machine was fixed during planning: global asdf Flutter moved `3.44.1-stable` → `3.47.1-stable` (Dart 3.12.1 → 3.13.1), and `very_good_cli` was reactivated at 1.5.0. Rollback: `asdf set --home flutter 3.44.1-stable`. The reactivated CLI does not reach the MCP server until the session restarts.

## References & Research

- Brainstorm: [docs/brainstorm/2026-09-17-claude-code-setup-brainstorm-doc.md](../brainstorm/2026-09-17-claude-code-setup-brainstorm-doc.md)
- Hook that blocks Bash test commands: `~/.claude/plugins/cache/very-good-claude-code-marketplace/vgv-ai-flutter-plugin/0.0.5/hooks/scripts/block-cli-workarounds.sh`
- `very_good_cli` version floor (`MIN_VERSION=1.3.0`) and the MCP auto-approve helper: same directory, `vgv-cli-common.sh`
- Wingspan's plugin-recommendation hook: `~/.claude/plugins/cache/very-good-claude-code-marketplace/vgv-wingspan/0.0.4/hooks/recommend-plugins.sh`
- The `^1.5.0` requirement and pub-workspace coverage bug: TODO comment in [.github/workflows/vgv_ai_cli.yaml](../../.github/workflows/vgv_ai_cli.yaml)
- CI's sanctioned `dart run test` form: `verify-version` job in the same workflow
- Settings schema (`enabledPlugins`, `extraKnownMarketplaces`, permission precedence, Bash rule limits): Claude Code docs at docs.claude.com — settings, permissions, discover-plugins, plugin-marketplaces

## Follow-ups to file

- **This repo:** widen the CI path filter in `.github/workflows/vgv_ai_cli.yaml` to include `**/*.md`, `.claude/**`, and `.github/cspell.json`. Today no job runs on a docs- or config-only PR, so `.github/cspell.json` cannot trigger the spell-check job that consumes it and new markdown reaches `main` unchecked. Flagged independently by the architecture and VGV reviews.
- **This repo:** enable branch protection on `main`, after deciding whether to require zero status checks or to split `semantic-pull-request` into its own unfiltered workflow.
- **Marketplace repo:** pin per-plugin `ref` values in `.claude-plugin/marketplace.json`. Without this, the catalog pin in step 1 freezes which versions are *listed* but not what installs.
- **Flutter plugin:** add a file-path or test-name filter to the `very_good_cli` MCP `test` tool. Until then `dart run test` is an undocumented workaround that risks becoming repo folklore.
- **Flutter plugin:** raise `MIN_VERSION` in `vgv-cli-common.sh`, or make it project-configurable. The current `1.3.0` floor stays silent for a repo that needs `^1.5.0`.
