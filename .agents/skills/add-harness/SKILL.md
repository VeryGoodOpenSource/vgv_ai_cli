---
name: add-harness
description: Adds support for a new coding agent harness to vgv_ai_cli — the Harness enum value, the agents brick folder and bundle, the HarnessTranslator, hook translation, and every test a new harness has to be added to. Use when asked to "add <agent> as a harness", "support <agent> in vgv_ai", "teach vgv_ai about <agent>", or to translate the VGV plugins for a coding agent the CLI does not configure yet. Also use when changing what an existing harness renders, since the same files and the same bundle regeneration are involved.
---

# Adding a harness

[ADDING_A_HARNESS.md](../../../ADDING_A_HARNESS.md) is the reference: the override table, the
brick variables, the path-to-`ChangeMode` rules. Read it before step 3. This file is the
procedure — what to do, in what order, and how to check each step landed.

Work from the repo root. Do not edit `lib/src/templates/agents_bundle.dart` by hand at any point;
it is generated.

## Step 0: research, then report before writing code

You cannot write the translator from the codebase alone. Install the harness's **latest** version,
record what `<executable> --version` prints, and read its **current** documentation — these tools
change their config format between minor releases, so neither your memory nor another harness's
layout is evidence. Fetch the page and quote it.

Answer these, with a source for each:

- The binary name, and what `<binary> --version` prints.
- The config directory under `$HOME`.
- Whether it reads `~/.agents/skills` with no configuration. If not, where it wants skills.
- Its settings file, and the key MCP servers go under.
- Whether it has subagents, and what frontmatter they take.
- Whether it has slash commands or prompts, and the folder name it reads them from.
- Whether anything in its config can run a shell command, and the event names it uses.

**Stop here and report the answers with their sources.** A guess at any of these produces config
that silently does nothing. If the documentation does not say, say so rather than inferring it
from another harness.

## Step 1: the enum value

Add the value to `Harness` in `packages/vgv_ai_cli/lib/src/model/harness.dart`, at the end.

Check: `cd packages/vgv_ai_cli && dart analyze --fatal-infos --fatal-warnings lib test` now fails
in `harness_test.dart` and `agents_vars_test.dart`, or those tests fail. That is expected — those
are the two lists step 6 fixes.

## Step 2: the brick

1. Add the boolean var to `bricks/agents/brick.yaml`.
2. Create `bricks/agents/__brick__/{{#<harness>}}<harness>/…{{\<harness>}}` holding **only** the
   files the harness actually reads. A feature it lacks gets no file — that absence is the opt-out,
   so do not add an empty folder or a placeholder.
3. Add a row to the capability matrix in `bricks/agents/README.md`.
4. Regenerate: `tool/generate_agents_bundle.sh` from the repo root.

Check: `git status` shows `packages/vgv_ai_cli/lib/src/templates/agents_bundle.dart` modified. If
it does not, the bundle did not regenerate and CI's `verify-bundle` job will fail. The script needs
`dart pub global activate mason_cli 0.1.4`.

## Step 3: the translator

Create `packages/vgv_ai_cli/lib/src/translate/translators/<harness>_translator.dart` with a
`HarnessTranslator` subclass. Override only what the harness differs on — see the override table
in the reference.

Rules that are easy to get wrong:

- **Return finished text.** `settings()`, and the `frontmatter`/`toml` on `HarnessFields`, are
  placed by the brick exactly as written. Mustache cannot escape JSON, TOML or YAML, so serialize
  in Dart.
- **Do not import another translator.** Shared behavior goes on the base class or in `translate/`.
- **Do not write a note saying the harness runs no hooks.** `Translator` adds that one itself when
  `hooks()` returns null.
- **Write a `TranslationNote` for everything the plugins ship that this harness has no home for** —
  agents it lacks, MCP servers it lacks, an event it does not have. Silence here is the failure
  mode: the user ends up thinking it was installed.

Then register it, both places:

- `export` it from `translators/translators.dart`, alphabetically.
- Add it to `harnessTranslators` in `translators/harness_translators.dart`, **in `Harness.values`
  order**.

Check: the `lists every harness once, in reporting order` test in `translator_test.dart` passes.

### When no existing override fits

Some harnesses need a capability the base class does not express yet. Antigravity needed three:
`skillsRoot()` on `HarnessTranslator`, an `instructions` key on `HarnessFields`, and a `harness`
argument on `SkillsTranslator` so a harness could own its skills copy.

That is a legitimate change, not a reason to bend the harness into an existing override. Add the
member with **a default that leaves every other harness unchanged**, then update the tests of the
shared type you touched — `harness_fields_test.dart`, `skills_translator_test.dart`,
`translator_test.dart` — not only your own. Say in the PR description which shared type you
extended and why.

## Step 4: hooks, only if its config runs a shell command

Skip this entirely otherwise — leave `hooks()` and `scripts` at their defaults and let the user get
the automatic note. OpenCode is the precedent: TypeScript callbacks, so no hooks.

`scripts` is **not** called by the framework. Nothing copies hook scripts unless your `hooks()`
calls `scripts.copy(...)` itself and puts `copy.files` and `copy.notes` into the `HookTranslation`
it returns. Overriding `scripts` alone copies nothing. Model the method on
`copilot_translator.dart`, which also plans the compat script as a file of its own.

Use `scripts.handlerNotes(hooks)` for the handler types the harness cannot run rather than
writing that note yourself — it is shared, and it already names the harness.

Write `<harness>_compat.dart` beside the translator for the preamble and the compat script, and
export it too. Start from `copilot_compat.dart`.

Check: a test that asserts the planned file tree for the harness includes the compat script and the
copied plugin hooks folder.

## Step 5: tests

Coverage must be 100%. Mock with `mocktail`, use `MemoryFileSystem.test()` for disk, and build
fixtures from the helpers in `test/src/translate/_assets.dart` rather than hand-rolling assets.

New:

- `test/src/translate/translators/<harness>_translator_test.dart`
- `test/src/translate/translators/<harness>_compat_test.dart` — only with hooks

Existing, all three must be updated or the suite fails:

- `test/src/model/harness_test.dart` — the reporting-order list **and** the config directory map
- `test/src/translate/agents_vars_test.dart` — the flags map
- `test/src/translate/translator_test.dart` — a `tree()` expectation for every file it gets

## Step 6: verify

```sh
cd packages/vgv_ai_cli
dart format --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings lib test
dart run test --run-skipped -t pinned-plugins
```

**Do not run `dart test`, `very_good test` or `flutter test` through Bash.** A hook in this repo
denies them as the first two tokens of a command. Run the full coverage suite through the
`very_good_cli` MCP `test` tool instead. `dart run test` is a different form and is allowed, which
is why the pinned-plugins command above works.

`pinned-plugins` resolves the real plugins over git and translates them for every harness,
including the new one. It is the check that the translator survives real input rather than
fixtures, and it is skipped by default, so run it explicitly.

## Step 7: the green gate

The suite passing is not the gate. The gate is that all four kinds of asset the plugins
contribute — **skills, subagents, hooks, MCP servers** — are each either ported or reported as
unsupported, with nothing silently missing.

Run it against the real harness, at the version you recorded in step 0:

```sh
<executable> --version
dart run bin/vgv_ai.dart install --only <harness> --check
dart run bin/vgv_ai.dart install --only <harness>
```

Then go through the four, one at a time:

| Asset | Passes when |
| --- | --- |
| Skills | The harness lists them, from `~/.agents/skills` or its own `skillsRoot()` |
| Subagents | The harness lists them, one file per agent |
| Hooks | A hook actually fires — not just that the files were written |
| MCP servers | The harness lists the servers as connected |

**The only acceptable reason for not porting one is that the harness does not support it**, with
its documentation as the evidence, and a `TranslationNote` saying so. "Not implemented yet",
"awkward to map" and "the schema wasn't clear" are unfinished work, not reasons. If the docs do not
settle it, say so and stop — do not ship a half-translated harness.

Files on disk prove nothing: a settings key in the wrong place writes cleanly and does nothing.
Confirm the harness loaded each one.

Then report: the harness version you tested, the four assets and how you confirmed each, every note
`install` printed and why that capability is genuinely unsupported, the files you changed, and the
output of the commands above. If you did not run one, or could not confirm one of the four, say so
plainly rather than implying it passed.

## Before opening a PR

Branch as `feat/<harness>-harness`, never commit to `main`, conventional commit messages. Do not
touch `CHANGELOG.md` or bump versions. Fill in `.github/PULL_REQUEST_TEMPLATE.md` and nothing more.
See [CONTRIBUTING.md](../../../CONTRIBUTING.md).

## Common failures

| Symptom | Cause |
| --- | --- |
| `verify-bundle` fails in CI | `tool/generate_agents_bundle.sh` was not run, or its output was not committed |
| The harness renders no files | No brick folder, or the folder name does not match the enum's `name` |
| Hook scripts are registered but absent on disk | `hooks()` never called `scripts.copy(...)` |
| Settings land escaped or mangled | A double mustache in the template instead of a triple |
| A path loop renders one nameless file | Its list was empty; `agents` and `commands` are omitted when empty |
| `dart analyze` reports `experiment_not_enabled_off_by_default` | Dart 3.12 is on the path. Fix the SDK — do not rewrite the `new(...)` constructors |
