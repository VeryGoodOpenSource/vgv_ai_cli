import 'package:file/file.dart';

/// {@template skill_asset}
/// A skill resolved from a plugin, in a harness-neutral shape.
///
/// Every field is portable: whatever only a parser's harness understands is
/// already interpreted ([description], [userInvocable],
/// [disableModelInvocation], [allowedTools]) or filtered out
/// ([portableFrontmatter]). [body] names the plugin's own files by their path
/// on disk, not through a harness's placeholder. [directory] is where it was
/// read from, for copying. [disableModelInvocation] keeps it the user's alone
/// to start.
/// {@endtemplate}
class const SkillAsset({
  /// The skill's name.
  required final String name,

  /// What the skill does and when to use it.
  required final String description,

  /// The skill's instructions, naming the plugin's files by their path.
  required final String body,

  /// Whether the user can invoke the skill by name.
  required final bool userInvocable,

  /// The tools the skill may use without asking.
  required final List<String> allowedTools,

  /// The frontmatter keys every harness understands, from [portableKeys].
  required final Map<String, Object?> portableFrontmatter,

  /// Where the skill was read from, for copying.
  required final Directory directory,

  /// Whether the skill is the user's alone to start.
  final bool disableModelInvocation = false,
}) {
  /// {@macro skill_asset}
  this;

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
