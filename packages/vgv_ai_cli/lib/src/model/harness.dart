/// {@template harness}
/// A coding agent harness `vgv_ai` knows how to configure.
///
/// [Harness.values] is the single source of truth for harness selection and
/// reporting. Adding a harness means adding an entry here and nothing else.
/// {@endtemplate}
enum Harness {
  /// Claude Code, which installs the VGV plugins from the marketplace.
  claude(displayName: 'Claude Code', executable: 'claude'),

  /// Gemini CLI.
  gemini(displayName: 'Gemini', executable: 'gemini'),

  /// Codex CLI.
  codex(displayName: 'Codex', executable: 'codex'),

  /// OpenCode.
  opencode(displayName: 'OpenCode', executable: 'opencode'),

  /// Pi.
  pi(displayName: 'Pi', executable: 'pi');

  /// {@macro harness}
  new({required this.displayName, required this.executable});

  /// A human readable name, for output.
  ///
  /// The enum's own [name] is the flag and reporting name, e.g. `opencode`.
  final String displayName;

  /// The binary looked for on the path.
  final String executable;
}
