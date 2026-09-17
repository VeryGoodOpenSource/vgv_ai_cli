/// {@template frontmatter_document}
/// A markdown file split into its YAML frontmatter and its body.
/// {@endtemplate}
class FrontmatterDocument {
  /// {@macro frontmatter_document}
  const new({required this.frontmatter, required this.body});

  /// Frontmatter keys mapped to their raw string value.
  ///
  /// Values are kept as strings rather than typed, because the plugins use
  /// scalars, folded blocks and inline lists interchangeably and every
  /// consumer here re-serializes them anyway.
  final Map<String, String> frontmatter;

  /// The document body, with the frontmatter removed.
  final String body;
}

/// Parses the small subset of YAML frontmatter the plugins actually use.
///
/// A full YAML parser is deliberately avoided. The plugins nest structures
/// that no harness reads back (`hooks:` inside an agent, for one), and a
/// strict parse would fail on them rather than passing them through.
abstract final class Frontmatter {
  /// Splits [source] into frontmatter and body.
  ///
  /// A document with no leading `---` block is returned with empty
  /// frontmatter and an unchanged body.
  static FrontmatterDocument parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return FrontmatterDocument(frontmatter: const {}, body: normalized);
    }

    final end = normalized.indexOf('\n---', 3);
    if (end == -1) {
      return FrontmatterDocument(frontmatter: const {}, body: normalized);
    }

    final raw = normalized.substring(4, end);
    final bodyStart = normalized.indexOf('\n', end + 1);
    final body = bodyStart == -1 ? '' : normalized.substring(bodyStart + 1);

    return FrontmatterDocument(
      frontmatter: _parseBlock(raw),
      body: body.trimLeft(),
    );
  }

  /// Re-serializes [frontmatter] into a `---` delimited block.
  static String render(Map<String, String> frontmatter) {
    if (frontmatter.isEmpty) return '';
    final buffer = StringBuffer('---\n');
    for (final MapEntry(:key, :value) in frontmatter.entries) {
      if (value.contains('\n')) {
        buffer.writeln('$key: |');
        for (final line in value.split('\n')) {
          buffer.writeln('  $line');
        }
      } else {
        buffer.writeln('$key: $value');
      }
    }
    return (buffer..writeln('---')).toString();
  }

  static Map<String, String> _parseBlock(String raw) {
    final result = <String, String>{};
    final lines = raw.split('\n');
    var index = 0;

    while (index < lines.length) {
      final line = lines[index];
      index++;
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      // Only top-level keys are captured; indented lines belong to the value
      // of the key above them.
      if (line.startsWith(' ') || line.startsWith('\t')) continue;

      final separator = line.indexOf(':');
      if (separator == -1) continue;

      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();

      // `|` and `>` introduce a block scalar; `description: |` and
      // `when_to_use: >` both appear in the plugins.
      final isBlockScalar = value == '|' || value == '>' || value == '>-';
      if (isBlockScalar || value.isEmpty) {
        final collected = <String>[];
        while (index < lines.length) {
          final next = lines[index];
          final isIndented = next.startsWith(' ') || next.startsWith('\t');
          if (next.trim().isNotEmpty && !isIndented) break;
          collected.add(next.trimLeft());
          index++;
        }
        while (collected.isNotEmpty && collected.last.trim().isEmpty) {
          collected.removeLast();
        }
        value = collected.join('\n').trim();
      }

      if (value.isNotEmpty) result[key] = value;
    }

    return result;
  }
}
