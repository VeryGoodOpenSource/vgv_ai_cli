/// {@template staged_fragment}
/// A config fragment the `agents` brick renders, and where it renders it.
/// {@endtemplate}
enum StagedFragment {
  /// Claude Code's settings: marketplace wiring and enabled plugins.
  claudeSettings('claude/settings.json'),

  /// Gemini CLI's settings.
  geminiSettings('gemini/settings.json'),

  /// Codex's config.
  codexConfig('codex/config.toml'),

  /// OpenCode's config.
  openCodeConfig('opencode/opencode.json'),

  /// Pi's settings.
  piSettings('pi/settings.json');

  /// {@macro staged_fragment}
  new(this.path);

  /// The path the brick renders this fragment at.
  final String path;
}

/// {@template staged_output}
/// The `agents` brick's rendered output.
///
/// Rendered into a temporary staging directory and read back into memory, so
/// `--check` stays a true dry run and nothing is generated into `$HOME`.
/// {@endtemplate}
class const StagedOutput(final Map<String, String> files) {
  /// The contents of [fragment], or `null` when the brick rendered none.
  String? operator [](StagedFragment fragment) => files[fragment.path];
}
