/// The `agents` brick's rendered output, keyed by the path the brick wrote it
/// at.
///
/// Rendered into a temporary staging directory and read back into memory, so
/// `--check` stays a true dry run and nothing is generated into `$HOME`.
typedef StagedOutput = Map<String, String>;

/// The paths the `agents` brick renders, as it renders them.
///
/// Named here rather than spelled inline in each translator, so a rename in
/// `bricks/agents/__brick__` breaks compilation instead of silently producing
/// a harness with no settings.
abstract final class StagedPaths {
  /// Claude Code's settings fragment: marketplace wiring and enabled plugins.
  static const claudeSettings = 'claude/settings.json';

  /// Gemini CLI's settings fragment.
  static const geminiSettings = 'gemini/settings.json';

  /// Codex's config fragment.
  static const codexConfig = 'codex/config.toml';

  /// OpenCode's config fragment.
  static const openCodeConfig = 'opencode/opencode.json';

  /// Pi's settings fragment.
  static const piSettings = 'pi/settings.json';
}
