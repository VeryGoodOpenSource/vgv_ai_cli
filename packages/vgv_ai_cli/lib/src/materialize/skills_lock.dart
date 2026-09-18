import 'dart:convert';

/// {@template locked_skill}
/// A single materialized skill's provenance in `skills-lock.json`.
///
/// [name] is the skill name, [path] is its repo-relative source (for example
/// `skills/plan`), and [target] is its `skills_root`-relative destination (for
/// example `vgv-wingspan/plan`).
/// {@endtemplate}
class const LockedSkill({
  required final String name,
  required final String path,
  required final String target,
}) {
  /// The lockfile JSON shape for a skill.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'path': path,
    'target': target,
  };
}

/// {@template locked_plugin}
/// A plugin's pinned origin and materialized skills in `skills-lock.json`.
/// {@endtemplate}
class const LockedPlugin({
  required final String repo,
  required final String ref,
  required final String commit,
  required final List<LockedSkill> skills,
}) {
  /// The lockfile JSON shape for a plugin.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'repo': repo,
    'ref': ref,
    'commit': commit,
    'skills': [for (final skill in skills) skill.toJson()],
  };
}

/// {@template skills_lock}
/// The `skills-lock.json` document that pins every materialized skill to its
/// remote origin, making installs reproducible.
/// {@endtemplate}
class const SkillsLock({
  required final String skillsRoot,
  required final Map<String, LockedPlugin> plugins,
  final int version = 1,
}) {
  /// The lockfile JSON shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'skillsRoot': skillsRoot,
    'plugins': <String, dynamic>{
      for (final MapEntry(:key, :value) in plugins.entries) key: value.toJson(),
    },
  };

  /// The resolved commit each plugin repo is pinned to, keyed by repo slug.
  ///
  /// Drives reproducible re-installs: without `--update`, plugins are fetched
  /// at these commits rather than their default branch head.
  static Map<String, String> pinsFromJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['plugins'] is! Map) {
      return const <String, String>{};
    }

    final pins = <String, String>{};
    for (final entry in (decoded['plugins'] as Map).values) {
      if (entry is! Map) continue;
      final repo = entry['repo'];
      final commit = entry['commit'];
      if (repo is String && commit is String) pins[repo] = commit;
    }
    return pins;
  }
}
