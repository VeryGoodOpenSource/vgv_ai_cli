import 'dart:collection';

/// {@template plugin_agent}
/// A single Claude subagent, parsed from one markdown file under `agents/`.
///
/// [model] is carried verbatim and never translated. Real plugins use
/// `inherit`, `sonnet`, and `haiku`, none of which mean anything to another
/// harness. Choosing what those become belongs to a per-harness mapping
/// config, not to parsing.
/// {@endtemplate}
class PluginAgent {
  /// {@macro plugin_agent}
  new({
    required this.id,
    required this.name,
    required this.description,
    this.model,
    this.effort,
    this.body = '',
    List<String> skills = const [],
    List<String> tools = const [],
    Map<String, dynamic> extra = const {},
  }) : skills = List.unmodifiable(skills),
       tools = List.unmodifiable(tools),
       extra = UnmodifiableMapView(Map.of(extra));

  /// The agent's path under `agents/` without its extension, for example
  /// `codebase-review/vgv-review-agent`.
  ///
  /// Always uses forward slashes, on every platform, so the manifest does not
  /// differ between macOS and Windows.
  final String id;

  /// The agent's declared name.
  final String name;

  /// The agent's description, verbatim.
  ///
  /// Often a multi-line block scalar carrying embedded `<examples>` XML.
  final String description;

  /// The agent's declared model, verbatim and untranslated.
  final String? model;

  /// The agent's declared reasoning effort, when present.
  final String? effort;

  /// The markdown following the frontmatter.
  final String body;

  /// Skills the agent declares.
  final List<String> skills;

  /// Tools the agent declares.
  final List<String> tools;

  /// Any frontmatter key this model does not name, including nested maps such
  /// as the `hooks:` block in `flutter-reviewer.md`.
  final Map<String, dynamic> extra;

  /// Normalises the several shapes a list-valued frontmatter key takes.
  ///
  /// Real plugins write `skills` as a flow sequence and as a block sequence,
  /// and `tools` as one comma separated string. All three become a list of
  /// trimmed, non-empty strings.
  static List<String> normalizeStringList(Object? value) {
    if (value == null) return const [];
    if (value is String) return _splitAndClean(value.split(','));
    if (value is List) {
      return _splitAndClean(value.map((e) => e.toString()));
    }
    return const [];
  }

  static List<String> _splitAndClean(Iterable<String> parts) =>
      parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  /// This agent as a JSON map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'model': model,
    'effort': effort,
    'skills': skills,
    'tools': tools,
    'body': body,
    'extra': extra,
  };
}
