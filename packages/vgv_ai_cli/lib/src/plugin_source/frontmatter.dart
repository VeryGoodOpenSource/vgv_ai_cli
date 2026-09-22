import 'package:yaml/yaml.dart';

/// {@template plugin_parse_exception}
/// Thrown when a plugin file exists but cannot be understood.
///
/// Deliberately not a [FormatException]. `YamlException` and `jsonDecode` both
/// throw `FormatException`, which the command runner catches and renders as a
/// CLI usage error, so a corrupt plugin file would otherwise tell the user
/// their command-line arguments were wrong.
/// {@endtemplate}
class const PluginParseException(final String path, final String message)
    implements Exception {
  @override
  String toString() => 'Could not parse $path: $message';
}

/// {@template frontmatter}
/// A markdown file's YAML frontmatter, parsed, plus the body beneath it.
///
/// [values] holds every frontmatter key with its parsed YAML value. [body] is
/// the document with the frontmatter block removed.
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

    return Frontmatter(
      // YAML admits non-string keys, such as an unquoted `2:`.
      values: {
        for (final entry in document.entries)
          '${entry.key}': _plain(entry.value),
      },
      body: lines.skip(end + 1).join('\n').trimLeft(),
    );
  }

  /// The declared `name`, or `null` when absent.
  String? get name => _string('name');

  /// The declared `description`, flattened onto one line.
  ///
  /// The plugins write descriptions as folded and literal block scalars, which
  /// carry newlines no index table or harness manifest wants.
  String get description => _oneLine(_string('description') ?? '');

  /// Skills the asset expects to have loaded.
  ///
  /// Written both inline as `[a, b]` and as a block sequence across the two
  /// plugins, so both parse to the same list.
  List<String> get skills => _stringList('skills');

  /// Tools the asset is allowed to use.
  ///
  /// Matched rather than split, because a tool may carry a parenthesized scope
  /// that contains the very separators a split would break on. Five wingspan
  /// skills ship entries like `Bash(git push *)` and `Bash(rm -rf docs/x/)`,
  /// which splitting on whitespace turns into `Bash(git`, `push` and `*)`.
  ///
  /// Separators are either spaces or commas: every skill uses spaces except
  /// `animations`, which uses commas.
  List<String> get allowedTools {
    final raw = _string('allowed-tools') ?? _string('tools');
    if (raw == null) return const [];
    return _toolPattern.allMatches(raw).map((match) => match[0]!).toList();
  }

  /// Whether the asset is meant to be invoked as a command.
  ///
  /// The Flutter plugin omits `user-invocable` entirely yet its skills are
  /// invocable, so an absent key means `true`.
  bool get userInvocable => values['user-invocable'] != false;

  String? _string(String key) {
    final value = values[key];
    return value == null ? null : '$value';
  }

  List<String> _stringList(String key) {
    final value = values[key];
    return switch (value) {
      null => const [],
      final Iterable<Object?> items => [
        for (final item in items)
          if ('$item'.trim().isNotEmpty) '$item'.trim(),
      ],
      _ => [
        for (final item in '$value'.split(','))
          if (item.trim().isNotEmpty) item.trim(),
      ],
    };
  }

  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// One tool name, plus an optional parenthesized scope that may itself
  /// contain spaces, commas and slashes.
  static final _toolPattern = RegExp(r'[\w.-]+(?:\([^)]*\))?');

  /// Converts parsed YAML into plain Dart collections.
  ///
  /// `loadYaml` returns `YamlMap` and `YamlList` for nested values, and agents
  /// nest `hooks:` several levels deep. Leaving those in place hands every
  /// downstream writer a type it may not serialize the same way, so the
  /// boundary is normalized here rather than in each translator.
  static Object? _plain(Object? value) => switch (value) {
    final YamlMap map => {
      for (final entry in map.entries) '${entry.key}': _plain(entry.value),
    },
    final YamlList list => [for (final item in list) _plain(item)],
    _ => value,
  };
}
