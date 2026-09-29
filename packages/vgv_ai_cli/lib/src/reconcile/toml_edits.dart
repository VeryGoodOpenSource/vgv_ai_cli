import 'package:collection/collection.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/line_endings.dart';

/// Decodes a TOML document, or null when it is malformed.
Map<String, dynamic>? decodeToml(String source) {
  try {
    return TomlDocument.parse(source).toMap();
  } on TomlException catch (_) {
    return null;
  }
}

/// Encodes a decoded map back to canonical TOML with a trailing newline.
String encodeToml(Map<String, dynamic> map) {
  final toml = TomlDocument.fromMap(map).toString().trim();
  return '$toml\n';
}

/// [original] with [merged] written into it as text, so the user's
/// comments, layout and unrelated keys survive, or null when no edit can.
///
/// [existing] is what [original] decodes to, and [added] is every key and
/// list entry [merged] holds that [existing] does not. Two edits are tried
/// in turn, and the first that decodes to exactly [merged] is kept.
/// Appending [added] covers new tables and arrays of tables. Upserting each
/// key that changed covers a key added to a table the user already has, or
/// a value VGV replaces. The file keeps its line endings.
String? editToml(
  String original, {
  required Map<String, dynamic> existing,
  required Map<String, dynamic> merged,
  required Map<String, dynamic> added,
}) {
  final (:text, :restore) = normalizeLineEndings(original);

  Iterable<String> edits() sync* {
    yield '${text.trimRight()}\n\n${encodeToml(added)}';
    yield _upsertChanged(text, existing, merged);
  }

  return edits()
      .map(restore)
      .firstWhereOrNull(
        (edit) => _deepEquality.equals(decodeToml(edit), merged),
      );
}

/// [text] with every value [merged] holds that [existing] does not
/// upserted into [table], and every table under it.
String _upsertChanged(
  String text,
  Map<String, dynamic> existing,
  Map<String, dynamic> merged, {
  List<String> table = const [],
}) {
  var edited = text;
  for (final MapEntry(:key, :value) in merged.entries) {
    final before = existing[key];
    if (value is Map<String, dynamic>) {
      edited = _upsertChanged(
        edited,
        before is Map<String, dynamic> ? before : const {},
        value,
        table: [...table, key],
      );
    } else if (!_deepEquality.equals(before, value)) {
      edited = upsertTomlKey(edited, table: table, key: key, value: value);
    }
  }
  return edited;
}

/// [text] with `key = value` set in the table at [table], and every other
/// line of it kept as written.
///
/// An empty [table] is the document's top level. A key already in the table
/// has its statement replaced, and the comment after it is kept, though a
/// comment inside a value that spans several lines is not. A new key goes
/// after the table's last key, and a table the document does not have is
/// appended at the end. So the user's comments, layout and every key VGV
/// does not set survive.
///
/// This edits text and never parses the whole document, so it trusts the
/// caller to check that the result parses to what it meant. A key spelled
/// as a dotted key, or a table only ever defined by `[[header]]`, is not
/// found here, and the check is what catches it.
String upsertTomlKey(
  String text, {
  required List<String> table,
  required String key,
  required Object? value,
}) {
  final lines = text.split('\n');
  final region = _region(_scan(lines), table);

  if (region == null) {
    final nested = table.reversed.fold<Map<String, dynamic>>({
      key: value,
    }, (inner, segment) => {segment: inner});
    final kept = text.trimRight();
    return '${kept.isEmpty ? '' : '$kept\n\n'}${_encode(nested)}\n';
  }

  final statement = _encode({key: value});
  final keys = region.body.where((s) => s.kind == _Kind.keyValue);
  final current = keys.firstWhereOrNull(
    (s) => _pathEquality.equals(s.path, [key]),
  );

  if (current != null) {
    lines.replaceRange(current.start, current.end + 1, [
      '$statement${current.comment}',
    ]);
  } else {
    final anchor = keys.lastOrNull ?? region.header;
    lines.insert(anchor == null ? 0 : anchor.end + 1, statement);
  }
  return lines.join('\n');
}

const _deepEquality = DeepCollectionEquality();

const _pathEquality = ListEquality<String>();

String _encode(Map<String, dynamic> map) => encodeToml(map).trimRight();

/// What a statement of a TOML document is.
enum _Kind {
  /// A `[table]` header.
  table,

  /// An `[[array of tables]]` header.
  arrayTable,

  /// A `key = value` pair, which may span several lines.
  keyValue,

  /// A blank line or a comment.
  other,
}

/// One statement, spanning the lines `start` to `end` inclusive. `path` is
/// the key of a pair or the name of a table, and empty otherwise. `comment`
/// is what follows the statement on its last line, from the whitespace
/// before its `#`, and empty when there is none.
typedef _Statement = ({
  _Kind kind,
  int start,
  int end,
  List<String> path,
  String comment,
});

/// The statements of one table: its header, null for the top level, and
/// every statement up to the next header.
typedef _Region = ({_Statement? header, List<_Statement> body});

/// The region of [statements] that holds [table], or null when the document
/// has no `[table]` header for it.
_Region? _region(List<_Statement> statements, List<String> table) {
  bool isHeader(_Statement s) =>
      s.kind == _Kind.table || s.kind == _Kind.arrayTable;

  if (table.isEmpty) {
    return (
      header: null,
      body: statements.takeWhile((s) => !isHeader(s)).toList(),
    );
  }

  final index = statements.indexWhere(
    (s) => s.kind == _Kind.table && _pathEquality.equals(s.path, table),
  );
  if (index == -1) return null;

  return (
    header: statements[index],
    body: statements.skip(index + 1).takeWhile((s) => !isHeader(s)).toList(),
  );
}

/// Splits [lines] into statements, so a multiline string or array is one.
List<_Statement> _scan(List<String> lines) {
  final statements = <_Statement>[];
  final scanner = _LineScanner();
  var start = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    scanner.feed(line);
    if (scanner.open && index < lines.length - 1) continue;

    final code = line.substring(0, scanner.comment).trimRight();
    statements.add(
      _classify(
        lines[start],
        start: start,
        end: index,
        comment: line.substring(code.length),
      ),
    );
    start = index + 1;
  }
  return statements;
}

/// Classifies the statement that begins with [first].
_Statement _classify(
  String first, {
  required int start,
  required int end,
  required String comment,
}) {
  final trimmed = first.trimLeft();
  final (kind, path) = switch (trimmed) {
    _ when trimmed.startsWith('[[') => (_Kind.arrayTable, const <String>[]),
    _ when trimmed.startsWith('[') => (
      _Kind.table,
      _keyPath(trimmed.substring(1), terminator: ']'),
    ),
    _ when trimmed.isEmpty || trimmed.startsWith('#') => (
      _Kind.other,
      const <String>[],
    ),
    _ => (_Kind.keyValue, _keyPath(trimmed, terminator: '=')),
  };
  return (kind: kind, start: start, end: end, path: path, comment: comment);
}

/// The dotted key at the start of [source], up to [terminator], or empty
/// when what is there is not a key.
///
/// The scan only finds where the key ends, stepping over quoted segments so
/// a [terminator] inside one does not end it. The key itself is decoded the
/// way TOML defines it.
List<String> _keyPath(String source, {required String terminator}) {
  var end = 0;
  while (end < source.length && source[end] != terminator) {
    end = switch (source[end]) {
      '"' => _skipBasic(source, end + 1),
      "'" => _skipLiteral(source, end + 1),
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
int _skipBasic(String line, int from) {
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
int _skipLiteral(String line, int from) {
  final close = line.indexOf("'", from);
  return close == -1 ? line.length : close + 1;
}

/// Tracks whether a statement is still open at the end of a line: inside a
/// multiline string, or an array or inline table that has not closed.
class _LineScanner {
  /// The delimiter of the multiline string the scan is inside, if any.
  String? _multiline;

  /// How many brackets and braces are open.
  var _depth = 0;

  /// Where the comment on the last line fed starts, or that line's length
  /// when it has none.
  int comment = 0;

  bool get open => _multiline != null || _depth > 0;

  void feed(String line) {
    comment = line.length;
    var index = 0;
    while (index < line.length) {
      index = _multiline == null
          ? _step(line, index)
          : _stepMultiline(line, index, _multiline!);
    }
  }

  /// Consumes what starts at [index] outside any string.
  int _step(String line, int index) {
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
        return _skipBasic(line, index + 1);
      case "'":
        return _skipLiteral(line, index + 1);
      case '[' || '{':
        _depth++;
      case ']' || '}':
        _depth--;
    }
    return index + 1;
  }

  /// Consumes what starts at [index] inside a multiline string closed by
  /// [delimiter].
  int _stepMultiline(String line, int index, String delimiter) {
    if (delimiter == '"""' && line[index] == r'\') return index + 2;
    if (!line.startsWith(delimiter, index)) return index + 1;

    _multiline = null;
    return index + delimiter.length;
  }
}
