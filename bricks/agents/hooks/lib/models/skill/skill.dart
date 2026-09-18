import 'package:json_annotation/json_annotation.dart';

part 'skill.g.dart';

/// {@template skill}
/// A skill resolved from the enabled plugins.
///
/// [name] identifies the skill and [description] tells the harness (or another
/// agent) when to use it. [path] is the canonical location the skill was
/// materialized to under the skills root, so harnesses that only ingest skills
/// through their instructions file can reference the single copy on disk.
/// {@endtemplate}
@JsonSerializable(createToJson: false)
class const Skill({
  required final String name,
  required final String description,
  final String path = '',
}) {
  /// Deserializes a [Skill] from the raw map supplied in `HookContext`.
  factory fromJson(Map<String, dynamic> json) => _$SkillFromJson(json);

  /// Deserializes the list of [Skill] supplied in `HookContext`.
  ///
  /// Mason vars arrive loosely typed, so non-map entries are dropped and each
  /// map is coerced before parsing.
  static List<Skill> listFromVars(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Skill.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Serializes the skill to JSON.
  ///
  /// [path] is omitted when empty so the instructions template can gate on its
  /// presence instead of rendering an empty reference.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'description': description,
    if (path.isNotEmpty) 'path': path,
  };
}
