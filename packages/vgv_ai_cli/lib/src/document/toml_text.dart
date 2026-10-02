import 'package:collection/collection.dart';
import 'package:vgv_ai_cli/src/document/model/model.dart';
import 'package:vgv_ai_cli/src/document/toml_scanner.dart';
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
  final String source, {

  /// Compares what an edit decodes to with what it meant to produce.
  final DocumentCodec codec = const DocumentCodec(),
}) {
  /// {@macro toml_text}
  ///
  /// [map] encoded as canonical TOML with a trailing newline.
  new encode(
    Map<String, dynamic> map, {
    DocumentCodec codec = const DocumentCodec(),
  }) : this(DocumentFormat.toml.encode(map), codec: codec);

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
      yield _withSource(text)
          ._rewrite(existing: existing, target: merged)
          .source;
    }

    return edits()
        .map((edit) => _withSource(restore(edit)))
        .firstWhereOrNull(
          (edit) => codec.deepEquality.equals(edit.decode(), merged),
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
    final edited = _withSource(text)
        ._rewrite(existing: existing, target: remaining)
        .source;
    final withdrawn = _withSource(restore('${edited.trimRight()}\n'));
    return codec.deepEquality.equals(withdrawn.decode(), remaining)
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
    final region = TomlScanner(lines).region(table: table);

    if (region == null) {
      final nested = table.reversed.fold<Map<String, dynamic>>({
        key: value,
      }, (inner, segment) => {segment: inner});
      final kept = source.trimRight();
      return _withSource(
        '${kept.isEmpty ? '' : '$kept\n\n'}${_encode(nested)}\n',
      );
    }

    final statement = _encode({key: value});
    final keys = region.body.where((s) => s.kind == TomlStatementKind.keyValue);
    final current = region.statementOf(key);

    if (current case TomlStatement(hasInnerComment: true)) return this;
    if (current != null) {
      lines.replaceRange(current.start, current.end + 1, [
        '$statement${current.comment}',
      ]);
    } else {
      final anchor = keys.lastOrNull ?? region.header;
      lines.insert(anchor == null ? 0 : anchor.end + 1, statement);
    }
    return _withSource(lines.join('\n'));
  }

  /// This text without the statement that sets [key] in [table], and
  /// unchanged when there is none.
  TomlText remove({required List<String> table, required String key}) {
    final lines = source.split('\n');
    final current = TomlScanner(lines).region(table: table)?.statementOf(key);
    if (current == null) return this;

    lines.removeRange(current.start, current.end + 1);
    return _withSource(lines.join('\n'));
  }

  /// This text without the `[table]` header and the blank lines under it,
  /// and unchanged when there is no such header.
  ///
  /// Called once the table's keys are gone. A comment directly above the
  /// next header is kept, since it describes that table rather than this
  /// one.
  TomlText removeTable(List<String> table) {
    final lines = source.split('\n');
    final region = TomlScanner(lines).region(table: table);
    final header = region?.header;
    if (header == null) return this;

    final body = region!.body;
    var kept = body.length;
    while (kept > 0 && lines[body[kept - 1].start].trimLeft().startsWith('#')) {
      kept--;
    }
    final last = kept == 0 ? header : body[kept - 1];

    lines.removeRange(header.start, last.end + 1);
    return _withSource(lines.join('\n'));
  }

  /// [source] as a [TomlText] that compares with this one's [codec].
  TomlText _withSource(String source) => TomlText(source, codec: codec);

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
      } else if (!codec.deepEquality.equals(before, value)) {
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

/// [map] as TOML statements, without the trailing newline.
String _encode(Map<String, dynamic> map) =>
    TomlText.encode(map).source.trimRight();
