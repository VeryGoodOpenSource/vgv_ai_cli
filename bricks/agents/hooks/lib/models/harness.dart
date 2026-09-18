/// A coding agent harness the brick knows how to configure.
///
/// [flag] is the boolean var name the brick reads to decide whether the
/// harness should be configured.
class const Harness(final String flag) {
  /// Claude Code.
  const new claude() : this('claude');

  /// Gemini CLI.
  const new gemini() : this('gemini');

  /// Codex.
  const new codex() : this('codex');

  /// OpenCode.
  const new opencode() : this('opencode');

  /// Pi.
  const new pi() : this('pi');
}
