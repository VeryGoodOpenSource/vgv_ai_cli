import 'package:json_annotation/json_annotation.dart';

part 'agent.g.dart';

/// {@template agent}
/// An agent resolved from the enabled plugins.
///
/// [name] identifies the agent and [description] tells the harness (or another
/// agent) when to delegate to it. Agents are surfaced through the shared
/// `AGENTS.md` listing only, so unlike a skill they carry no on-disk path.
/// {@endtemplate}
@JsonSerializable()
class const Agent({
  required final String name,
  required final String description,
}) {
  /// Deserializes an [Agent] from the raw map supplied in `HookContext`.
  factory fromJson(Map<String, dynamic> json) => _$AgentFromJson(json);

  /// Deserializes the list of [Agent] supplied in `HookContext`.
  ///
  /// Mason vars arrive loosely typed, so non-map entries are dropped and each
  /// map is coerced before parsing.
  static List<Agent> listFromVars(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Agent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Serializes the agent to JSON.
  Map<String, dynamic> toJson() => _$AgentToJson(this);
}
