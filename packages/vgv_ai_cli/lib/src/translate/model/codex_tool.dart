import 'package:collection/collection.dart';

/// {@template codex_tool}
/// A tool Claude Code names in a hook matcher, and the names Codex answers to
/// for the same tool.
///
/// Only the tools the two harnesses spell differently are listed. Every other
/// name carries over untouched, `Bash` and the `mcp__<server>__<tool>` form
/// the MCP matchers are written in included, which is what [codexNamesOf]
/// returns for a name no entry claims.
/// {@endtemplate}
enum CodexTool {
  /// Codex answers to `Edit` in a matcher, so this adds a name rather than
  /// fixing a miss. It is Codex's own: a file edit arrives as `apply_patch`
  /// and reports `tool_name: apply_patch`, so without it the file names only
  /// tools Codex never reports, and the matcher rests on an alias it
  /// documents but need not keep.
  edit(claude: 'Edit', codex: ['Edit', _applyPatch]),

  /// {@macro codex_tool}
  write(claude: 'Write', codex: ['Write', _applyPatch]),

  /// Codex has no tool that reads a file: it reads through the shell. So a
  /// hook that watches reads watches `Bash`, the tool Codex reads with.
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

  /// The names Codex answers to for [claudeName].
  ///
  /// A name no entry claims is one both harnesses spell the same way, so it
  /// comes back as itself.
  static List<String> codexNamesOf(String claudeName) =>
      values.firstWhereOrNull((tool) => tool.claude == claudeName)?.codex ??
      [claudeName];
}
