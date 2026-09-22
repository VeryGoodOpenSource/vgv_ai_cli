import 'package:file/file.dart';

/// {@template skill_asset}
/// A skill resolved from a plugin, in a harness-neutral shape.
///
/// Every field is portable: whatever only a parser's harness understands is
/// already interpreted ([userInvocable], [allowedTools]) or filtered out
/// ([portableFrontmatter]). [directory] is where it was read from, for copying.
/// {@endtemplate}
class const SkillAsset({
  required final String name,
  required final String description,
  required final String body,
  required final bool userInvocable,
  required final List<String> allowedTools,
  required final Map<String, Object?> portableFrontmatter,
  required final Directory directory,
}) {
  /// The frontmatter keys every harness understands: the open Agent Skills
  /// specification's key set. Parsers keep exactly these and drop everything
  /// else, so a harness-specific key never reaches another harness's skill.
  ///
  /// An allowlist, not a denylist: the keys a harness invents are open-ended,
  /// so a denylist would silently miss new ones.
  static const portableKeys = <String>{
    'name',
    'description',
    'license',
    'compatibility',
    'metadata',
    'allowed-tools',
  };
}
