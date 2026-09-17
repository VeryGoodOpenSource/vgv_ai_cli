import 'package:yaml/yaml.dart';

/// A markdown document split into its YAML frontmatter and its body.
typedef ParsedDocument = ({Map<String, dynamic> data, String body});

const _fence = '---';

/// Splits [source] into its YAML frontmatter map and its markdown body.
///
/// Frontmatter is only recognised when the very first line is exactly `---`
/// and a later line is exactly `---`. Matching the fence exactly is load
/// bearing: agent and skill bodies contain `---` as a markdown rule, and
/// splitting on every occurrence truncates them silently.
///
/// A document with no frontmatter yields an empty map and the whole document
/// as its body.
///
/// Throws a [FormatException] when the frontmatter is not a YAML mapping, and
/// lets [YamlException] escape when the YAML itself is malformed. Callers are
/// expected to translate both into a `PluginException` carrying the file path.
ParsedDocument splitFrontmatter(String source) {
  final normalized = source.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');

  if (lines.first != _fence) {
    return (data: const {}, body: normalized.trim());
  }

  final end = lines.indexOf(_fence, 1);
  if (end == -1) {
    return (data: const {}, body: normalized.trim());
  }

  final body = lines.sublist(end + 1).join('\n').trim();
  final yamlSource = lines.sublist(1, end).join('\n');
  final document = loadYaml(yamlSource);

  if (document == null) return (data: const {}, body: body);
  if (document is! YamlMap) {
    throw const FormatException('frontmatter is not a mapping');
  }

  return (data: toSortedJson(document)! as Map<String, dynamic>, body: body);
}

/// Converts [value] into plain Dart collections that `jsonEncode` accepts,
/// with every map's keys stringified and sorted.
///
/// Handles both the `yaml` package's node types and the plain maps and lists
/// `jsonDecode` produces, because `YamlMap` and `YamlList` are themselves a
/// [Map] and a [List]. Sorting is what makes the emitted manifest
/// byte-identical regardless of the key order in the source file.
Object? toSortedJson(Object? value) {
  if (value is YamlScalar) return toSortedJson(value.value);
  if (value is Map) {
    final entries =
        value.entries
            .map((e) => MapEntry(e.key.toString(), toSortedJson(e.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, dynamic>.fromEntries(entries);
  }
  if (value is List) return value.map(toSortedJson).toList();
  return value;
}
