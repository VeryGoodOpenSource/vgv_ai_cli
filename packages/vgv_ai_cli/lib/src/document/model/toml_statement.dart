import 'package:collection/collection.dart';

/// {@template toml_statement_kind}
/// What a statement of a TOML document is.
/// {@endtemplate}
enum TomlStatementKind {
  /// A `[table]` header.
  table,

  /// An `[[array of tables]]` header.
  arrayTable,

  /// A `key = value` pair, which may span several lines.
  keyValue,

  /// A blank line or a comment.
  other,
}

/// {@template toml_statement}
/// One statement of a TOML document.
/// {@endtemplate}
class const TomlStatement({
  /// What the statement is.
  required final TomlStatementKind kind,

  /// The first line of the statement.
  required final int start,

  /// The last line of the statement, inclusive.
  required final int end,

  /// The key of a pair or the name of a table, and empty otherwise.
  required final List<String> path,

  /// What follows the statement on its last line, from the whitespace before
  /// its `#`, and empty when there is none.
  required final String comment,

  /// Whether a comment sits on a line of the statement before its last,
  /// inside a value that spans several lines.
  required final bool hasInnerComment,
}) {
  /// {@macro toml_statement}
  this;

  /// Whether the statement opens a table or an array of tables.
  bool get isHeader =>
      kind == TomlStatementKind.table || kind == TomlStatementKind.arrayTable;

  /// Whether the statement is a [kind] statement for exactly [path].
  bool declares(TomlStatementKind kind, List<String> path) =>
      this.kind == kind && const ListEquality<String>().equals(this.path, path);
}
