import 'package:collection/collection.dart';

/// {@template codex_tool}
/// A tool Claude Code names in a hook matcher and the names Codex answers to
/// for it. Only tools spelled differently are listed; any other name carries
/// over as itself.
/// {@endtemplate}
enum CodexTool {
  /// Codex accepts `Edit` in a matcher but reports `apply_patch`, so both
  /// are named.
  edit(claude: 'Edit', codex: ['Edit', _applyPatch]),

  /// {@macro codex_tool}
  write(claude: 'Write', codex: ['Write', _applyPatch]),

  /// Codex reads files through the shell, so a hook on reads watches `Bash`.
  read(claude: 'Read', codex: [_shell]),

  /// {@macro codex_tool}
  glob(claude: 'Glob', codex: [_shell]),

  /// {@macro codex_tool}
  grep(claude: 'Grep', codex: [_shell]);

  /// {@macro codex_tool}
  new({required this.claude, required this.codex});

  /// The one tool Codex edits files with, whatever the matcher named.
  static const _applyPatch = 'apply_patch';

  /// The tool Codex runs commands, and so reads files, with.
  static const _shell = 'Bash';

  /// Claude Code's name for this tool, as a hook matcher spells it.
  final String claude;

  /// Every name Codex may report for it.
  final List<String> codex;

  /// The names Codex answers to for [claudeName], or the name itself.
  static List<String> codexNamesOf(String claudeName) =>
      values.firstWhereOrNull((tool) => tool.claude == claudeName)?.codex ??
      [claudeName];
}
