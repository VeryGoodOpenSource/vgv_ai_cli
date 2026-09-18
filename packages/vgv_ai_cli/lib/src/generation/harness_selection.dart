/// {@template harness_selection}
/// The set of harnesses the `install` command renders configuration for.
///
/// Each flag maps directly onto the matching `agents` brick var, so the brick
/// emits only the selected harnesses' files.
/// {@endtemplate}
class const HarnessSelection({
  final bool claude = false,
  final bool gemini = false,
  final bool codex = false,
  final bool opencode = false,
  final bool pi = false,
}) {
  /// A selection with every harness enabled.
  static const all = HarnessSelection(
    claude: true,
    gemini: true,
    codex: true,
    opencode: true,
    pi: true,
  );

  /// Whether no harness is selected.
  bool get isEmpty => !claude && !gemini && !codex && !opencode && !pi;

  /// The brick vars that gate which harness files are rendered.
  Map<String, dynamic> toVars() => <String, dynamic>{
    'claude': claude,
    'gemini': gemini,
    'codex': codex,
    'opencode': opencode,
    'pi': pi,
  };
}
