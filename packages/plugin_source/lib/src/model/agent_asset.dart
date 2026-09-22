/// {@template agent_asset}
/// A subagent resolved from a plugin, in a harness-neutral shape.
/// {@endtemplate}
class const AgentAsset({
  required final String name,
  required final String description,
  required final String body,
  required final List<String> skills,
});
