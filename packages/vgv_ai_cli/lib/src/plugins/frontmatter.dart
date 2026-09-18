import 'package:yaml/yaml.dart';

/// Parses the leading YAML frontmatter block of a markdown [content] string.
///
/// Frontmatter is the `---` delimited YAML block at the very top of the file:
///
/// ```markdown
/// ---
/// name: plan
/// description: Plan work.
/// ---
/// ```
///
/// Returns the decoded key/value pairs, or `null` when the content has no
/// frontmatter block or the block fails to parse. Plugin markdown is authored
/// by hand, so a malformed block is treated as "absent" rather than fatal.
Map<String, dynamic>? parseFrontmatter(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) return null;

  final end = normalized.indexOf('\n---', 4);
  if (end == -1) return null;

  final block = normalized.substring(4, end);
  try {
    final decoded = loadYaml(block);
    if (decoded is! Map) return null;
    return <String, dynamic>{
      for (final MapEntry(:key, :value) in decoded.entries) '$key': value,
    };
  } on YamlException {
    return null;
  }
}
