import 'package:vgv_ai_cli/src/plugin_source/format/config_map.dart';
import 'package:vgv_ai_cli/src/plugin_source/format/plugin_parse_exception.dart';
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

  /// The declared `description`, flattened onto one line.
  ///
  /// The plugins write descriptions as folded and literal block scalars, which
  /// carry newlines no index table or harness manifest wants.
  String get description => _oneLine(config.string('description') ?? '');

  /// Skills the asset expects to have loaded.
  ///
  /// Written both inline as `[a, b]` and as a block sequence across the two
  /// plugins, so both parse to the same list.
  List<String> get skills => config.stringList('skills');

  static String _oneLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
