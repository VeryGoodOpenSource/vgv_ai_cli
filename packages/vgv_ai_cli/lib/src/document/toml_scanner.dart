import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/document/model/model.dart';

/// {@template toml_scanner}
/// Scans the TOML document [lines] into statements, so a multiline string
/// or array is one statement however many lines it spans.
/// {@endtemplate}
class TomlScanner(final List<String> lines) {
  /// The region of [lines] that holds [table], or null when the document
  /// has no `[table]` header for it. An empty [table] is the document's top
  /// level.
  TomlRegion? region({required List<String> table}) {
    final statements = _scan();
    if (table.isEmpty) {
      return TomlRegion(
        header: null,
        body: statements.takeWhile((s) => !s.isHeader).toList(),
      );
    }

    final index = statements.indexWhere(
      (s) => s.declares(TomlStatementKind.table, table),
    );
    if (index == -1) return null;

    return TomlRegion(
      header: statements[index],
      body: statements.skip(index + 1).takeWhile((s) => !s.isHeader).toList(),
    );
  }

  /// Splits [lines] into statements, so a multiline string or array is one.
  List<TomlStatement> _scan() {
    final statements = <TomlStatement>[];
    final scanner = _LineScanner(multiline: null, depth: 0, comment: 0);
    var start = 0;
    var hasInnerComment = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      scanner.feed(line);
      if (scanner.open && index < lines.length - 1) {
        hasInnerComment = hasInnerComment || scanner.comment < line.length;
        continue;
      }

      final code = line.substring(0, scanner.comment).trimRight();
      statements.add(
        _classify(
          lines[start],
          start: start,
          end: index,
          comment: line.substring(code.length),
          hasInnerComment: hasInnerComment,
        ),
      );
      start = index + 1;
      hasInnerComment = false;
    }
    return statements;
  }

  /// Classifies the statement that begins with [first].
  static TomlStatement _classify(
    String first, {
    required int start,
    required int end,
    required String comment,
    required bool hasInnerComment,
  }) {
    final trimmed = first.trimLeft();
    final kind = switch (trimmed) {
      _ when trimmed.startsWith('[[') => TomlStatementKind.arrayTable,
      _ when trimmed.startsWith('[') => TomlStatementKind.table,
      _ when trimmed.isEmpty || trimmed.startsWith('#') =>
        TomlStatementKind.other,
      _ => TomlStatementKind.keyValue,
    };
    final path = switch (kind) {
      TomlStatementKind.table => _keyPath(
        trimmed.substring(1),
        terminator: ']',
      ),
      TomlStatementKind.keyValue => _keyPath(trimmed, terminator: '='),
      TomlStatementKind.arrayTable ||
      TomlStatementKind.other => const <String>[],
    };
    return TomlStatement(
      kind: kind,
      start: start,
      end: end,
      path: path,
      comment: comment,
      hasInnerComment: hasInnerComment,
    );
  }

  /// The dotted key at the start of [source], up to [terminator], or empty
  /// when what is there is not a key.
  ///
  /// The scan only finds where the key ends, stepping over quoted segments
  /// so a [terminator] inside one does not end it. The key itself is decoded
  /// the way TOML defines it.
  static List<String> _keyPath(String source, {required String terminator}) {
    var end = 0;
    while (end < source.length && source[end] != terminator) {
      end = switch (source[end]) {
        '"' => _skipBasic(source, from: end + 1),
        "'" => _skipLiteral(source, from: end + 1),
        _ => end + 1,
      };
    }

    try {
      final key = TomlKey.parse(source.substring(0, end));
      return [for (final part in key.parts) part.name];
    } on TomlException catch (_) {
      return const [];
    }
  }

  /// The index just past the basic string's closing quote, starting inside
  /// it at [from].
  static int _skipBasic(String line, {required int from}) {
    for (var index = from; index < line.length; index++) {
      if (line[index] == r'\') {
        index++;
      } else if (line[index] == '"') {
        return index + 1;
      }
    }
    return line.length;
  }

  /// The index just past the literal string's closing quote, starting inside
  /// it at [from].
  static int _skipLiteral(String line, {required int from}) {
    final close = line.indexOf("'", from);
    return close == -1 ? line.length : close + 1;
  }
}

/// Tracks whether a statement is still open at the end of a line: inside a
/// multiline string, or an array or inline table that has not closed.
///
/// It holds the delimiter of the multiline string the scan is inside, if
/// any, how many brackets and braces are open, and where the comment on the
/// last line fed starts, or that line's length when it has none.
class _LineScanner({
  required var String? _multiline,
  required var int _depth,
  required var int comment,
}) {
  bool get open => _multiline != null || _depth > 0;

  void feed(String line) {
    comment = line.length;
    var index = 0;
    while (index < line.length) {
      index = _multiline == null
          ? _step(line, index: index)
          : _stepMultiline(line, index: index, delimiter: _multiline!);
    }
  }

  /// Consumes what starts at [index] outside any string.
  int _step(String line, {required int index}) {
    for (final delimiter in const ['"""', "'''"]) {
      if (line.startsWith(delimiter, index)) {
        _multiline = delimiter;
        return index + delimiter.length;
      }
    }

    switch (line[index]) {
      case '#':
        comment = index;
        return line.length;
      case '"':
        return TomlScanner._skipBasic(line, from: index + 1);
      case "'":
        return TomlScanner._skipLiteral(line, from: index + 1);
      case '[' || '{':
        _depth++;
      case ']' || '}':
        _depth--;
    }
    return index + 1;
  }

  /// Consumes what starts at [index] inside a multiline string closed by
  /// [delimiter].
  int _stepMultiline(
    String line, {
    required int index,
    required String delimiter,
  }) {
    if (delimiter == '"""' && line[index] == r'\') return index + 2;
    if (!line.startsWith(delimiter, index)) return index + 1;

    _multiline = null;
    return index + delimiter.length;
  }
}
