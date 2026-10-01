import 'dart:convert';

import 'package:plugin_source/src/format/config_map.dart';
import 'package:plugin_source/src/format/plugin_parse_exception.dart';
import 'package:yaml/yaml.dart';

/// {@template frontmatter}
/// A markdown file's YAML frontmatter, parsed, plus the body beneath it.
///
/// [config] holds every frontmatter key with its normalized value, read through
/// the shared [ConfigMap] accessors. [body] is the document with the
/// frontmatter block removed.
/// {@endtemplate}
class const Frontmatter({
  required final ConfigMap config,
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

    // YAML admits non-string keys, such as an unquoted `2:`; ConfigMap
    // stringifies them.
    return Frontmatter(
      config: ConfigMap.of(document),
      body: lines.skip(end + 1).join('\n').trimLeft(),
    );
  }

  /// The declared `name`, or `null` when absent.
  String? get name => config.string('name');

  /// The declared `description`, flattened onto one line, or `''` when absent.
  String get description => oneLine('description') ?? '';

  /// Skills the asset expects to have loaded.
  ///
  /// Written both inline as `[a, b]` and as a block sequence across the two
  /// plugins, so both parse to the same list.
  List<String> get skills => config.stringList('skills');

  /// The value under [key], flattened onto one line, or `null` when absent.
  ///
  /// The plugins write their prose keys as folded and literal block scalars,
  /// which carry newlines no index table or harness manifest wants.
  String? oneLine(String key) =>
      config.string(key)?.replaceAll(_whitespace, ' ').trim();

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
