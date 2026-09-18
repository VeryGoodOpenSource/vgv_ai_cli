/// {@template agent}
/// An agent resolved from a VGV plugin.
///
/// [name] and [description] come from the agent markdown file's frontmatter.
/// Agents are surfaced to non-Claude harnesses through the shared `AGENTS.md`
/// listing only, so unlike a skill they carry no on-disk path.
/// {@endtemplate}
class const Agent({
  required final String name,
  required final String description,
}) {
  /// The mason var shape the `agents` brick reads for a single agent.
  Map<String, dynamic> toVars() => <String, dynamic>{
    'name': name,
    'description': description,
  };
}
