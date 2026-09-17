import 'package:json_annotation/json_annotation.dart';

part 'named_entry.g.dart';

/// {@template named_entry}
/// A named entry resolved from the enabled plugins.
///
/// Agents and skills share the same shape: [name] identifies the entry and
/// [description] tells the harness (or another agent) when to use it.
/// {@endtemplate}
@JsonSerializable()
class const NamedEntry(final String name, final String description) {
  /// Deserializes a [NamedEntry] from the raw map supplied in `HookContext`.
  factory fromJson(Map<String, dynamic> json) => _$NamedEntryFromJson(json);

  /// Deserializes the list of [NamedEntry] supplied in `HookContext`.
  ///
  /// Mason vars arrive loosely typed, so non-map entries are dropped and each
  /// map is coerced before parsing.
  static List<NamedEntry> listFromVars(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => NamedEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Serializes the entry to JSON.
  Map<String, dynamic> toJson() => _$NamedEntryToJson(this);
}
