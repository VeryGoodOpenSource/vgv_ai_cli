import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/cli.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Configures OpenCode.
///
/// Mapping follows the hand-built translation on the wingspan repo's
/// `feat/opencode-plugin` branch: agents collapse to `description` plus
/// `mode: subagent`, and commands keep their body with a single `description`.
class OpenCodeHarness extends Harness {
  /// Creates an [OpenCodeHarness].
  const new();

  @override
  String get name => 'opencode';

  @override
  String get displayName => 'OpenCode';

  @override
  Future<bool> detected({required Logger logger}) =>
      OpenCodeCli.installed(logger: logger);

  @override
  Directory configRoot(Directory home) =>
      Directory(p.join(home.path, '.config', 'opencode'));

  @override
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = configRoot(home);
    final changes = <PlannedChange>[];

    final config = staged['opencode.fragment.json'];
    if (config != null) {
      changes.add(
        merge(
          File(p.join(root.path, 'opencode.json')),
          config,
          ChangeMode.mergeJson,
        ),
      );
    }

    final block = staged['vgv_block.md'];
    if (block != null) {
      changes.add(
        merge(File(p.join(root.path, 'AGENTS.md')), block, ChangeMode.block),
      );
    }

    for (final agent in assets.agents) {
      changes.add(
        own(
          File(p.join(root.path, 'agents', '${agent.name}.md')),
          Translate.agent(agent, {
            'description': agent.description,
            'mode': 'subagent',
          }, skillsRoot: agentsSkillsRoot(home)),
        ),
      );
    }

    for (final skill in assets.skills.where((s) => s.userInvocable)) {
      changes.add(
        own(
          File(p.join(root.path, 'commands', '${skill.name}.md')),
          '---\ndescription: ${skill.description}\n---\n\n${skill.body}',
        ),
      );
    }

    return changes;
  }
}
