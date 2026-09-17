/// {@template plugin_source}
/// Where a plugin's files came from.
///
/// [resolvedSha] is null until a fetch layer resolves [ref] to a commit.
/// {@endtemplate}
class PluginSource {
  /// {@macro plugin_source}
  const new({required this.repo, required this.ref, this.resolvedSha});

  /// The git remote the plugin was cloned from.
  final String repo;

  /// The tag or ref requested.
  final String ref;

  /// The commit [ref] resolved to, when known.
  final String? resolvedSha;

  /// This source as a JSON map.
  Map<String, dynamic> toJson() => {
    'repo': repo,
    'ref': ref,
    'resolvedSha': resolvedSha,
  };
}
