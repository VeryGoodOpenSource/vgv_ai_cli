import 'package:json_annotation/json_annotation.dart';

part 'agent.g.dart';

/// {@template agent}
/// An agent resolved from the enabled plugins.
///
/// [name] identifies the agent and [description] tells the harness when to
/// dispatch it.
/// {@endtemplate}
@JsonSerializable()
class const Agent(final String name, final String description) {
  /// Deserializes an [Agent] from the raw map supplied in `HookContext`.
  factory fromJson(Map<String, dynamic> json) => _$AgentFromJson(json);

  /// Serializes the agent to JSON.
  Map<String, dynamic> toJson() => _$AgentToJson(this);
}
