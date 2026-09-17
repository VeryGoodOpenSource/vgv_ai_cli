import 'package:json_annotation/json_annotation.dart';

part 'pi_settings.g.dart';

/// {@template pi_settings}
/// The settings fragment merged into `~/.pi/agent/settings.json`.
/// {@endtemplate}
@JsonSerializable(createFactory: false)
class const PiSettings(final List<String> skills) {
  /// Serializes the settings fragment to JSON.
  Map<String, dynamic> toJson() => _$PiSettingsToJson(this);
}
