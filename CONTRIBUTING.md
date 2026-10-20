# Contributing to vgv_ai_cli

Thanks for taking the time! This guide is the short version — [AGENTS.md](AGENTS.md) holds the
architecture, conventions and the full command reference, and it applies to humans as much as to
coding agents.

## Open an issue first

Please [open an issue](https://github.com/VeryGoodOpenSource/vgv_ai_cli/issues/new/choose) before
you open a pull request, so we can agree on the fix before you put work into it.

## Set up

Install the prerequisites in [AGENTS.md](AGENTS.md#prerequisites) — the Dart version matters, on
3.12 the analyzer reports errors against this codebase's 3.13 syntax. Then, from the repo root:

```sh
dart pub get
```

The [repo README](README.md#contributor-setup) covers the committed agent configuration.

## Before you open the pull request

```sh
# From packages/vgv_ai_cli
dart format .
dart analyze --fatal-infos --fatal-warnings lib test
```

Run the test suite as [AGENTS.md](AGENTS.md#common-commands) describes. Pull requests without 100%
coverage will not be merged.

Branch from `main`, and use a [conventional commit](https://www.conventionalcommits.org/en/v1.0.0)
message — the `semantic-pull-request` check enforces it on the PR title, and release-please reads
it to build the changelog.

## Releases

[release-please](https://github.com/googleapis/release-please) owns versions and changelogs. Every
push to `main` opens or updates a release pull request that bumps `pubspec.yaml`, regenerates
`lib/src/version.dart` and writes `CHANGELOG.md`. Merge it only when a release is intended; merging
it tags the release and publishes the GitHub release notes.

Do not bump versions or edit a `CHANGELOG.md` by hand.
