import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/generation/skill_target.dart';
import 'package:vgv_ai_cli/src/materialize/skills_lock.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

/// {@template skill_materializer}
/// Copies each resolved skill once into the skills root and records its origin
/// in `skills-lock.json`.
///
/// Skills are namespaced under `<skillsRoot>/<plugin>/<skill>` so the single
/// copy is the shared "partial" every harness references. Copy (not symlink) is
/// used for cross-platform safety; the lockfile — not the filesystem — is what
/// tracks which paths are managed.
/// {@endtemplate}
class const SkillMaterializer({
  final JsonEncoder encoder = const JsonEncoder.withIndent('  '),
}) {
  /// Materializes every skill in [plugins] into [destination] and writes the
  /// lockfile.
  ///
  /// [destination] is the resolved skills-root directory on disk; [skillsRoot]
  /// is the display path (typically `~`-prefixed) recorded in the lockfile.
  Future<SkillsLock> materialize({
    required ResolvedPlugins plugins,
    required Directory destination,
    required String skillsRoot,
  }) async {
    final locked = <String, LockedPlugin>{};

    for (final plugin in plugins.plugins) {
      final lockedSkills = <LockedSkill>[];
      for (final entry in plugin.skills) {
        final source = Directory(p.join(plugin.directory.path, entry.source));
        if (!source.existsSync()) continue;

        final target = skillTarget(plugin: plugin.name, source: entry.source);
        final targetDirectory = Directory(
          p.joinAll([destination.path, ...p.posix.split(target)]),
        );
        _copyDirectory(source, targetDirectory);

        lockedSkills.add(
          LockedSkill(
            name: entry.skill.name,
            path: p.split(entry.source).join('/'),
            target: target,
          ),
        );
      }

      if (lockedSkills.isNotEmpty) {
        locked[plugin.name] = LockedPlugin(
          repo: plugin.repo,
          ref: plugin.ref,
          commit: plugin.commit,
          skills: lockedSkills,
        );
      }
    }

    final lock = SkillsLock(skillsRoot: skillsRoot, plugins: locked);
    final lockFile = File(p.join(destination.path, 'skills-lock.json'));
    await lockFile.create(recursive: true);
    await lockFile.writeAsString('${encoder.convert(lock.toJson())}\n');

    return lock;
  }

  /// Replaces [target] with a fresh recursive copy of [source].
  ///
  /// The target is cleared first so a re-install never leaves stale files from
  /// a skill that shed content between commits.
  void _copyDirectory(Directory source, Directory target) {
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);

    for (final entity in source.listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: source.path);
      final destinationPath = p.join(target.path, relative);
      if (entity is Directory) {
        Directory(destinationPath).createSync(recursive: true);
      } else if (entity is File) {
        File(destinationPath).parent.createSync(recursive: true);
        entity.copySync(destinationPath);
      }
    }
  }
}
