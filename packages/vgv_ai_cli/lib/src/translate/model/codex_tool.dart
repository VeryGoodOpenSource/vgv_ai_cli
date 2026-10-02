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
  /// A captured payload names Codex's file-edit tool `apply_patch`, so
  /// `Edit` alone would never match. It keeps its own name as well, because
  /// Codex documents all three as interchangeable here and an extra
  /// alternative costs nothing.
  edit(claude: 'Edit', codex: ['Edit', 'apply_patch']),

  /// {@macro codex_tool}
  write(claude: 'Write', codex: ['Write', 'apply_patch']),

  /// Codex reads files through the shell, so this names no tool it has and a
  /// matcher of nothing but these could never fire.
  read(claude: 'Read', codex: []),

  /// {@macro codex_tool}
  glob(claude: 'Glob', codex: []),

  /// {@macro codex_tool}
  grep(claude: 'Grep', codex: []);

  /// {@macro codex_tool}
  new({required this.claude, required this.codex});

  /// Claude Code's name for this tool, as a hook matcher spells it.
  final String claude;

  /// Every name Codex may report for it, and empty when Codex has no such
  /// tool.
  final List<String> codex;

  /// The names Codex answers to for [claudeName].
  ///
  /// A name no entry claims is one both harnesses spell the same way, so it
  /// comes back as itself.
  static List<String> codexNamesOf(String claudeName) =>
      values.firstWhereOrNull((tool) => tool.claude == claudeName)?.codex ??
      [claudeName];
}
