import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Writes the canonical skill copy every non-Claude harness reads.
///
/// This is planned once rather than per harness. `~/.agents/skills` is on
/// Gemini's, Codex's, OpenCode's and Pi's discovery paths, so four harnesses
/// share one copy and there is nothing to keep in sync.
class SkillsWriter {
  /// Creates a [SkillsWriter].
  const new();

  /// Plans the canonical skills, plus each skill's bundled files.
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
  }) {
    final root = agentsSkillsRoot(home);
    final changes = <PlannedChange>[];

    for (final skill in assets.skills) {
      final target = Directory(p.join(root, skill.name));
      changes.add(
        PlannedChange(
          file: File(p.join(target.path, 'SKILL.md')),
          contents: Translate.skill(skill),
          mode: ChangeMode.own,
          harness: 'shared',
        ),
      );

      // `references/`, `scripts/` and the two skills that use a flat
      // `reference.md` instead all travel with the skill.
      for (final entity in skill.directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: skill.directory.path);
        if (relative == 'SKILL.md') continue;
        changes.add(
          PlannedChange(
            file: File(p.join(target.path, relative)),
            contents: entity.readAsStringSync(),
            mode: ChangeMode.own,
            harness: 'shared',
          ),
        );
      }
    }

    return changes;
  }
}
