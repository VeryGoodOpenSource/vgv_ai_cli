/// The `agents` brick's rendered output, keyed by the path the brick wrote it
/// at.
///
/// Rendered into a temporary staging directory and read back into memory, so
/// `--check` stays a true dry run and nothing is generated into `$HOME`.
typedef StagedOutput = Map<String, String>;

/// The paths the `agents` brick renders, as it renders them.
///
/// One source of truth for the five paths, rather than the same string
/// literal spelled out in each translator. It is not a compile-time guarantee:
/// these are plain constants, so a rename in `bricks/agents/__brick__` still
/// surfaces at runtime, as the `TranslationNote` for an absent fragment.
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

  /// Every fragment a translator claims, for checking against the brick.
  static const values = <String>[
    claudeSettings,
    geminiSettings,
    codexConfig,
    openCodeConfig,
    piSettings,
  ];
}
