import 'package:collection/collection.dart';
import 'package:vgv_ai_cli/src/document/model/toml_statement.dart';

/// {@template toml_region}
/// The statements of one table of a TOML document.
/// {@endtemplate}
class const TomlRegion({
  /// The table's header, null for the top level.
  required final TomlStatement? header,

  /// Every statement after [header] up to the next header.
  required final List<TomlStatement> body,
}) {
  /// {@macro toml_region}
  this;

  /// The statement that sets [key] in this table, if any.
  TomlStatement? statementOf(String key) => body.firstWhereOrNull(
    (s) => s.declares(TomlStatementKind.keyValue, [key]),
  );
}
