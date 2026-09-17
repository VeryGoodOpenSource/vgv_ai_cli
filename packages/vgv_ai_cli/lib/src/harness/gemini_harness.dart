import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/cli.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Configures Gemini CLI.
///
/// Gemini reads `~/.agents/skills` and has native subagents, so the only real
/// translation is its commands, which are TOML rather than markdown.
class GeminiHarness extends Harness {
  /// Creates a [GeminiHarness].
  const new();

  @override
  String get name => 'gemini';

  @override
  String get displayName => 'Gemini CLI';

  @override
  Future<bool> detected({required Logger logger}) =>
      GeminiCli.installed(logger: logger);

  @override
  Directory configRoot(Directory home) =>
      Directory(p.join(home.path, '.gemini'));

  @override
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = configRoot(home);
    final changes = <PlannedChange>[];

    final settings = staged['gemini_settings.fragment.json'];
    if (settings != null) {
      changes.add(
        merge(
          File(p.join(root.path, 'settings.json')),
          settings,
          ChangeMode.mergeJson,
        ),
      );
    }

    final block = staged['vgv_block.md'];
    if (block != null) {
      changes.add(
        merge(File(p.join(root.path, 'GEMINI.md')), block, ChangeMode.block),
      );
    }

    // Native subagents, flattened out of their category directories.
    for (final agent in assets.agents) {
      changes.add(
        own(
          File(p.join(root.path, 'agents', '${agent.name}.md')),
          Translate.agent(agent, {
            'name': agent.name,
            'description': agent.description,
          }, skillsRoot: agentsSkillsRoot(home)),
        ),
      );
    }

    // Commands are TOML here, and `$ARGUMENTS` becomes `{{args}}`.
    for (final skill in assets.skills.where((s) => s.userInvocable)) {
      changes.add(
        own(
          File(p.join(root.path, 'commands', '${skill.name}.toml')),
          _command(skill),
        ),
      );
    }

    return changes;
  }

  String _command(SkillAsset skill) {
    final prompt = skill.body.replaceAll(r'$ARGUMENTS', '{{args}}');
    return '''
description = ${Translate.tomlString(skill.description)}
prompt = ${Translate.tomlMultiline(prompt)}
''';
  }
}
