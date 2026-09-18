import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';
import 'package:yaml/yaml.dart';

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
        for (final entry in document.entries) '${entry.key}': entry.value,
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
  /// Space-separated in every skill except `animations`, which uses commas.
  /// Splitting on either avoids branching per plugin.
  List<String> get allowedTools {
    final raw = _string('allowed-tools') ?? _string('tools');
    if (raw == null) return const [];
    return raw
        .split(RegExp(r'[,\s]+'))
        .where((tool) => tool.isNotEmpty)
        .toList();
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
}
