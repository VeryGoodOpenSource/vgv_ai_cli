import 'dart:convert';

import 'package:ack/ack.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:plugin_source/src/format/plugin_schema.dart';
import 'package:yaml/yaml.dart';

/// {@template frontmatter}
/// A markdown file's YAML frontmatter, parsed, plus the body beneath it.
///
/// [values] holds every frontmatter key, with nested values as plain
/// `Map<String, Object?>` and `List<Object?>`. The keys every format shares
/// are validated by [schema]; a parser validates its own keys against its own
/// schema. [body] is the document with the frontmatter block removed.
/// {@endtemplate}
class const Frontmatter({
  required final Map<String, Object?> values,
  required final String body,
}) {
  /// Parses [source], which must open and close with a `---` fence.
  ///
  /// [path] names the file in any [PluginParseException].
  factory parse(String source, {required String path}) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');

    if (lines.first.trim() != '---') {
      throw PluginParseException(path, 'no opening --- frontmatter fence');
    }

    // The closing fence is a line equal to exactly `---`. Searching for the
    // substring instead would match a markdown horizontal rule in the body and
    // swallow half the document.
    final end = lines.indexWhere((line) => line.trim() == '---', 1);
    if (end == -1) {
      throw PluginParseException(path, 'unterminated frontmatter fence');
    }

    final Object? document;
    try {
      document = loadYaml(lines.sublist(1, end).join('\n'));
    } on FormatException catch (error) {
      // YamlException implements FormatException, which the command runner
      // renders as a CLI usage error. Convert it before it escapes.
      throw PluginParseException(path, error.message);
    }

    if (document is! YamlMap) {
      throw PluginParseException(
        path,
        'frontmatter must be a set of key/value pairs, got '
        '${document == null ? 'nothing' : document.runtimeType}',
      );
    }

    _checkKeys(document, pointer: '#', path: path);
    return Frontmatter(
      values: schema.decode(_plain.decode(document, path: path), path: path),
      body: lines.skip(end + 1).join('\n').trimLeft(),
    );
  }

  /// The frontmatter keys every format shares. `skills` is written both as a
  /// list and as one comma-separated string.
  static final ObjectSchema schema = Ack.object({
    'name': Ack.string().optional(),
    'description': Ack.string().optional(),
    'skills': Ack.anyOf([Ack.list(Ack.string()), Ack.string()]).optional(),
  }).passthrough();

  /// Normalizes YAML collections into plain Dart ones, which a passthrough
  /// object schema alone leaves as `YamlMap` and `YamlList`.
  static final MapSchema<Object, Object> _plain = Ack.map(Ack.any().nullable());

  /// Throws, naming the first key under [value] that is not a string, at any
  /// depth.
  ///
  /// YAML admits non-string keys, such as an unquoted `2:`, which the schema
  /// would reject with a message that does not name the key.
  static void _checkKeys(
    Object? value, {
    required String pointer,
    required String path,
  }) {
    switch (value) {
      case final Map<Object?, Object?> map:
        for (final MapEntry(:key, value: child) in map.entries) {
          if (key is! String) {
            throw PluginParseException(
              path,
              '$pointer: key $key must be a string',
            );
          }
          _checkKeys(child, pointer: jsonPointer(pointer, key), path: path);
        }
      case final List<Object?> items:
        for (final (index, item) in items.indexed) {
          _checkKeys(item, pointer: jsonPointer(pointer, index), path: path);
        }
    }
  }

  /// The declared `name`, or `null` when absent.
  String? get name => values['name'] as String?;

  /// The declared `description`, flattened onto one line, or `''` when absent.
  String get description => oneLine('description') ?? '';

  /// Skills the asset expects to have loaded, blank entries dropped.
  ///
  /// Written both inline as `[a, b]` and as a block sequence across the two
  /// plugins, so both parse to the same list. A string is split on commas.
  List<String> get skills {
    final items = switch (values['skills']) {
      final String line => line.split(','),
      final list => list as List<String>? ?? const [],
    };
    return [
      for (final item in items)
        if (item.trim().isNotEmpty) item.trim(),
    ];
  }

  /// The string under [key], flattened onto one line, or `null` when absent.
  ///
  /// The plugins write their prose keys as folded and literal block scalars,
  /// which carry newlines no index table or harness manifest wants. A schema
  /// must have validated [key] as a string.
  String? oneLine(String key) =>
      (values[key] as String?)?.replaceAll(_whitespace, ' ').trim();

  static final _whitespace = RegExp(r'\s+');

  /// Renders [values] as a fenced YAML frontmatter block, closing newline
  /// included. An empty [values] renders an empty string rather than an empty
  /// fence, which no harness reads as valid.
  ///
  /// Lives beside `Frontmatter.parse` so the two round-trip against each other
  /// in one test file. Strings are always quoted rather than emitted plain:
  /// deciding when a scalar is safe unquoted is a pile of branches over YAML's
  /// indicator characters, reserved words and number forms, and quoting is
  /// correct in every one of those cases. A JSON string is a valid YAML
  /// double-quoted scalar, so `jsonEncode` does the quoting.
  static String render(Map<String, Object?> values) {
    if (values.isEmpty) return '';
    final buffer = StringBuffer('---\n');
    for (final MapEntry(:key, :value) in values.entries) {
      buffer.write(_renderEntry(key, value, indent: ''));
    }
    buffer.write('---\n');
    return buffer.toString();
  }

  static String _renderEntry(
    String key,
    Object? value, {
    required String indent,
  }) => switch (value) {
    final Map<String, Object?> map when map.isNotEmpty => [
      '$indent$key:\n',
      for (final entry in map.entries)
        _renderEntry(entry.key, entry.value, indent: '$indent  '),
    ].join(),
    final List<Object?> items when items.isNotEmpty => [
      '$indent$key:\n',
      for (final item in items)
        '$indent  - ${_scalar(item, indent: '$indent  ')}\n',
    ].join(),
    _ => '$indent$key: ${_scalar(value, indent: indent)}\n',
  };

  /// Renders one scalar owned by a key or list dash at [indent].
  ///
  /// A string carrying newlines becomes a literal block scalar, because the
  /// plugins write descriptions as folded and literal blocks and a quoted
  /// `\n` would be unreadable in a file people open. The `2` indentation
  /// indicator places its lines two columns past their owner, so a first line
  /// that starts with spaces keeps them rather than setting the indentation.
  ///
  /// Throws an [ArgumentError] for a collection inside a list, which no
  /// harness frontmatter needs.
  static String _scalar(Object? value, {required String indent}) =>
      switch (value) {
        null => '',
        Map(isNotEmpty: true) ||
        List(isNotEmpty: true) => throw ArgumentError.value(
          value,
          'value',
          'a list item must be a scalar',
        ),
        final String text when text.contains('\n') => [
          '|2-\n',
          for (final line in text.trimRight().split('\n')) '$indent  $line\n',
        ].join().trimRight(),
        final String text => jsonEncode(text),
        final bool flag => '$flag',
        final num number => '$number',
        // An empty map or list, or anything else, has no useful YAML form as a
        // scalar; stringify and quote it rather than emit a broken document.
        _ => jsonEncode('$value'),
      };
}
