import 'package:file/file.dart';

/// {@template skill_asset}
/// A skill resolved from a plugin, in a harness-neutral shape.
///
/// Every field is portable: whatever a parser knew that only Claude Code
/// understands has already been interpreted ([userInvocable], [allowedTools])
/// or filtered out ([portableFrontmatter]), so no consumer of this model can
/// reach back for a Claude-only key.
///
/// [directory] is where the skill was read from, so `references/` and
/// `scripts/` can be copied alongside it.
/// {@endtemplate}
class const SkillAsset({
  required final String name,
  required final String description,
  required final String body,
  required final bool userInvocable,
  required final List<String> allowedTools,
  required final Map<String, Object?> portableFrontmatter,
  required final Directory directory,
});
