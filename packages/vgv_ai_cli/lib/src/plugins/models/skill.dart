/// {@template skill}
/// A skill resolved from a VGV plugin.
///
/// [name] and [description] come from the skill's `SKILL.md` frontmatter.
/// [path] is the canonical on-disk location the skill is materialized to under
/// `skills_root`, so every harness can reference the single copy rather than
/// inlining its body.
/// {@endtemplate}
class const Skill({
  required final String name,
  required final String description,
  final String path = '',
}) {
  /// Returns a copy of this skill with its canonical [path] set.
  Skill withPath(String path) =>
      Skill(name: name, description: description, path: path);

  /// The mason var shape the `agents` brick reads for a single skill.
  Map<String, dynamic> toVars() => <String, dynamic>{
    'name': name,
    'description': description,
    if (path.isNotEmpty) 'path': path,
  };
}
