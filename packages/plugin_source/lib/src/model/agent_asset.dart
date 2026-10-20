/// {@template agent_asset}
/// A subagent resolved from a plugin, in a harness-neutral shape.
/// {@endtemplate}
class const AgentAsset({
  /// The agent's name, safe to use as a file name.
  required final String name,

  /// What the agent does, on one line.
  required final String description,

  /// The agent's instructions: its markdown file below the frontmatter.
  required final String body,

  /// The skills the agent expects to have loaded.
  required final List<String> skills,
}) {
  /// {@macro agent_asset}
  this;
}
