import 'dart:collection';

/// {@template plugin_metadata}
/// The contents of a plugin's `.claude-plugin/plugin.json`.
///
/// Every field except [name] is optional: `vgv-wingspan` ships no `license`,
/// and other plugins omit other keys. Unrecognised keys are kept in [extra] so
/// metadata is as lossless as the agents themselves.
/// {@endtemplate}
class PluginMetadata {
  /// {@macro plugin_metadata}
  new({
    required this.name,
    this.version,
    this.description,
    this.author,
    this.homepage,
    this.repository,
    this.license,
    List<String> keywords = const [],
    Map<String, dynamic> extra = const {},
  }) : keywords = List.unmodifiable(keywords),
       extra = UnmodifiableMapView(Map.of(extra));

  /// The plugin's name.
  final String name;

  /// The plugin's version, when declared.
  final String? version;

  /// The plugin's description, when declared.
  final String? description;

  /// The plugin's author, carried verbatim because its shape varies.
  final Object? author;

  /// The plugin's homepage, when declared.
  final String? homepage;

  /// The plugin's repository, when declared.
  final String? repository;

  /// The plugin's license, when declared.
  final String? license;

  /// The plugin's keywords.
  final List<String> keywords;

  /// Any `plugin.json` key this model does not name.
  final Map<String, dynamic> extra;

  /// This metadata as a JSON map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'description': description,
    'author': author,
    'homepage': homepage,
    'repository': repository,
    'license': license,
    'keywords': keywords,
    'extra': extra,
  };
}
