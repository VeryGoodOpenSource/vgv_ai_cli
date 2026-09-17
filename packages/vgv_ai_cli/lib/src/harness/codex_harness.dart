import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/cli.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Configures Codex.
///
/// Codex reads `~/.agents/skills` and `AGENTS.md` natively. Its subagents are
/// TOML rather than markdown, and its prompts directory is flat with no
/// subdirectories.
class CodexHarness extends Harness {
  /// Creates a [CodexHarness].
  const new();

  @override
  String get name => 'codex';

  @override
  String get displayName => 'Codex';

  @override
  Future<bool> detected({required Logger logger}) =>
      CodexCli.installed(logger: logger);

  @override
  Directory configRoot(Directory home) =>
      Directory(p.join(home.path, '.codex'));

  @override
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = configRoot(home);
    final changes = <PlannedChange>[];

    final config = staged['codex_config.fragment.toml'];
    if (config != null) {
      changes.add(
        merge(
          File(p.join(root.path, 'config.toml')),
          config,
          ChangeMode.mergeToml,
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
          File(p.join(root.path, 'agents', '${agent.name}.toml')),
          _agent(agent, agentsSkillsRoot(home)),
        ),
      );
    }

    for (final skill in assets.skills.where((s) => s.userInvocable)) {
      changes.add(
        own(File(p.join(root.path, 'prompts', '${skill.name}.md')), skill.body),
      );
    }

    return changes;
  }

  /// Codex requires `name`, `description` and `developer_instructions`.
  String _agent(AgentAsset agent, String skillsRoot) {
    final instructions = Translate.agent(
      agent,
      const {},
      skillsRoot: skillsRoot,
    ).trimLeft();
    return '''
name = ${Translate.tomlString(agent.name)}
description = ${Translate.tomlString(agent.description)}
developer_instructions = ${Translate.tomlMultiline(instructions)}
''';
  }
}
