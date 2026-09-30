import 'package:collection/collection.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/document/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template toml_text}
/// The text of a TOML document, edited as text so the user's comments,
/// layout and unrelated keys survive.
///
/// `TomlDocument` keeps only the values a document parses to, so writing one
/// back drops every comment. Every edit here works on [source] instead, and
/// parsing is only ever used to check what an edit produced.
/// {@endtemplate}
class const TomlText(
  /// The document's text, as written.
  final String source,
) {
  /// {@macro toml_text}
  ///
  /// [map] encoded as canonical TOML with a trailing newline.
  new encode(Map<String, dynamic> map) : this(DocumentFormat.toml.encode(map));

  /// What [source] decodes to, or null when it is malformed.
  Map<String, dynamic>? decode() => DocumentFormat.toml.decode(source);

  /// This text with [merged] written into it, or null when no edit can.
  ///
  /// [existing] is what [source] decodes to, and [added] is every key and
  /// list entry [merged] holds that [existing] does not. Two edits are tried
  /// in turn, and the first that decodes to exactly [merged] is kept.
  /// Appending [added] covers new tables and arrays of tables. Upserting each
  /// key that changed covers a key added to a table the user already has, or
  /// a value VGV replaces. The text keeps its line endings.
  TomlText? edit({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> merged,
    required Map<String, dynamic> added,
  }) {
    final NormalizedText(:text, :restore) = NormalizedText.from(source);

    Iterable<String> edits() sync* {
      yield '${text.trimRight()}\n\n${TomlText.encode(added).source}';
      yield TomlText(text)._rewrite(existing: existing, target: merged).source;
    }

    return edits()
        .map((edit) => TomlText(restore(edit)))
        .firstWhereOrNull(
          (edit) => _codec.deepEquality.equals(edit.decode(), merged),
        );
  }

  /// This text with [existing], what it decodes to, taken down to
  /// [remaining], or null when the edit does not decode to exactly
  /// [remaining].
  ///
  /// Each value that differs is upserted, each key [remaining] drops is
  /// removed, and so is each table it drops, so every line VGV does not
  /// change is kept as written. Install appends after a blank line, so what
  /// is left at the end of the text is trimmed back to one line ending.
  TomlText? withdraw({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> remaining,
  }) {
    final NormalizedText(:text, :restore) = NormalizedText.from(source);
    final edited = TomlText(text)
        ._rewrite(existing: existing, target: remaining)
        .source;
    final withdrawn = TomlText(restore('${edited.trimRight()}\n'));
    return _codec.deepEquality.equals(withdrawn.decode(), remaining)
        ? withdrawn
        : null;
  }

  /// This text with `key = value` set in the table at [table], and every
  /// other line of it kept as written.
  ///
  /// An empty [table] is the document's top level. A key already in the table
  /// has its statement replaced, and the comment after it is kept. A value
  /// that spans several lines with a comment inside it is left as it is,
  /// since replacing it would drop that comment. A new key goes
  /// after the table's last key, and a table the document does not have is
  /// appended at the end. So the user's comments, layout and every key VGV
  /// does not set survive.
  ///
  /// This edits text and never parses the whole document, so it trusts the
  /// caller to check that the result parses to what it meant. A key spelled
  /// as a dotted key, or a table only ever defined by `[[header]]`, is not
  /// found here, and the check is what catches it.
  TomlText upsert({
    required List<String> table,
    required String key,
    required Object? value,
  }) {
    final lines = source.split('\n');
    final region = _region(_scan(lines), table: table);

    if (region == null) {
      final nested = table.reversed.fold<Map<String, dynamic>>({
        key: value,
      }, (inner, segment) => {segment: inner});
      final kept = source.trimRight();
      return TomlText('${kept.isEmpty ? '' : '$kept\n\n'}${_encode(nested)}\n');
    }

    final statement = _encode({key: value});
    final keys = region.body.where((s) => s.kind == TomlStatementKind.keyValue);
    final current = _find(region, key);

    if (current case TomlStatement(hasInnerComment: true)) return this;
    if (current != null) {
      lines.replaceRange(current.start, current.end + 1, [
        '$statement${current.comment}',
      ]);
    } else {
      final anchor = keys.lastOrNull ?? region.header;
      lines.insert(anchor == null ? 0 : anchor.end + 1, statement);
    }
    return TomlText(lines.join('\n'));
  }

  /// This text without the statement that sets [key] in [table], and
  /// unchanged when there is none.
  TomlText remove({required List<String> table, required String key}) {
    final lines = source.split('\n');
    final region = _region(_scan(lines), table: table);
    final current = region == null ? null : _find(region, key);
    if (current == null) return this;

    lines.removeRange(current.start, current.end + 1);
    return TomlText(lines.join('\n'));
  }

  /// This text without the `[table]` header and the blank lines under it,
  /// and unchanged when there is no such header.
  ///
  /// Called once the table's keys are gone. A comment directly above the
  /// next header is kept, since it describes that table rather than this
  /// one.
  TomlText removeTable(List<String> table) {
    final lines = source.split('\n');
    final region = _region(_scan(lines), table: table);
    final header = region?.header;
    if (header == null) return this;

    final body = region!.body;
    var kept = body.length;
    while (kept > 0 && lines[body[kept - 1].start].trimLeft().startsWith('#')) {
      kept--;
    }
    final last = kept == 0 ? header : body[kept - 1];

    lines.removeRange(header.start, last.end + 1);
    return TomlText(lines.join('\n'));
  }

  /// This text edited so it holds [target] where it held [existing], its
  /// decoded form at [table]: every value that differs upserted, and every
  /// key and table [target] drops removed.
  TomlText _rewrite({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> target,
    List<String> table = const [],
  }) {
    var edited = this;
    for (final MapEntry(:key, :value) in target.entries) {
      final before = existing[key];
      if (value is Map<String, dynamic>) {
        edited = edited._rewrite(
          existing: before is Map<String, dynamic> ? before : const {},
          target: value,
          table: [...table, key],
        );
      } else if (!_codec.deepEquality.equals(before, value)) {
        edited = edited.upsert(table: table, key: key, value: value);
      }
    }

    for (final MapEntry(:key, :value) in existing.entries) {
      if (target.containsKey(key)) continue;

      final path = [...table, key];
      edited = value is Map<String, dynamic>
          ? edited
                ._rewrite(existing: value, target: const {}, table: path)
                .removeTable(path)
          : edited.remove(table: table, key: key);
    }
    return edited;
  }
}

/// The statement that sets [key] in [region], if any.
TomlStatement? _find(TomlRegion region, String key) =>
    region.body.firstWhereOrNull(
      (s) =>
          s.kind == TomlStatementKind.keyValue &&
          _pathEquality.equals(s.path, [key]),
    );

const _pathEquality = ListEquality<String>();

/// [map] as TOML statements, without the trailing newline.
String _encode(Map<String, dynamic> map) =>
    TomlText.encode(map).source.trimRight();

/// The region of [statements] that holds [table], or null when the document
/// has no `[table]` header for it.
TomlRegion? _region(
  List<TomlStatement> statements, {
  required List<String> table,
}) {
  if (table.isEmpty) {
    return TomlRegion(
      header: null,
      body: statements.takeWhile((s) => !s.isHeader).toList(),
    );
  }

  final index = statements.indexWhere(
    (s) =>
        s.kind == TomlStatementKind.table &&
        _pathEquality.equals(s.path, table),
  );
  if (index == -1) return null;

  return TomlRegion(
    header: statements[index],
    body: statements.skip(index + 1).takeWhile((s) => !s.isHeader).toList(),
  );
}

/// Splits [lines] into statements, so a multiline string or array is one.
List<TomlStatement> _scan(List<String> lines) {
  final statements = <TomlStatement>[];
  final scanner = _LineScanner();
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
TomlStatement _classify(
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
    TomlStatementKind.table => _keyPath(trimmed.substring(1), terminator: ']'),
    TomlStatementKind.keyValue => _keyPath(trimmed, terminator: '='),
    TomlStatementKind.arrayTable || TomlStatementKind.other => const <String>[],
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
/// The scan only finds where the key ends, stepping over quoted segments so
/// a [terminator] inside one does not end it. The key itself is decoded the
/// way TOML defines it.
List<String> _keyPath(String source, {required String terminator}) {
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
int _skipBasic(String line, {required int from}) {
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
int _skipLiteral(String line, {required int from}) {
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
        return _skipBasic(line, from: index + 1);
      case "'":
        return _skipLiteral(line, from: index + 1);
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

const _codec = DocumentCodec();
