import 'package:json_annotation/json_annotation.dart';

part 'skill.g.dart';

/// {@template skill}
/// A skill resolved from the enabled plugins.
///
/// [name] identifies the skill and [description] tells an agent when to load
/// it.
/// {@endtemplate}
@JsonSerializable()
class const Skill(final String name, final String description) {
  /// Deserializes a [Skill] from the raw map supplied in `HookContext`.
  factory fromJson(Map<String, dynamic> json) => _$SkillFromJson(json);

  /// Serializes the skill to JSON.
  Map<String, dynamic> toJson() => _$SkillToJson(this);
}
