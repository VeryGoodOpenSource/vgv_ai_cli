import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/agent_markdown.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/hook_event_map.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_tool_map.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template codex_translator}
/// Configures Codex.
///
/// Codex reads `~/.agents/skills` natively. Its subagents are TOML rather than
/// markdown, and its prompts directory is flat with no subdirectory support.
/// {@endtemplate}
class const CodexTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.codex;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = p.join(home.path, '.codex');
    final fs = home.fileSystem;
    final skillsRoot = agentsSkillsRoot(home).path;
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    final config = stagedContents(
      staged: staged,
      path: StagedPaths.codexConfig,
      target: fs.file(p.join(root, 'config.toml')),
      notes: notes,
    );
    if (config != null) {
      changes.add(
        PlannedChange.mergeToml(
          file: fs.file(p.join(root, 'config.toml')),
          contents: config,
          harness: harness,
        ),
      );
    }

    for (final agent in assets.agents) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'agents', '${agent.name}.toml')),
          contents: _agent(agent, skillsRoot),
          harness: harness,
        ),
      );
    }

    // Prompts are flat; Codex reads no subdirectories here.
    for (final skill in assets.invocableSkills) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'prompts', '${skill.name}.md')),
          contents: McpToolMap.rewrite(skill.body),
          harness: harness,
        ),
      );
    }

    // Codex reads hooks from either hooks.json or inline [hooks] tables in
    // config.toml. A separate file keeps one format per concern and leaves the
    // config fragment a single change.
    final hooks = buildHookDocument(
      assets.hooks,
      home: home,
      events: codexEvents,
      timeoutScale: 1,
      harnessName: 'Codex',
      notes: notes,
    );
    if (hooks.isNotEmpty) {
      changes.add(
        PlannedChange.mergeJson(
          file: fs.file(p.join(root, 'hooks.json')),
          contents: jsonEncode({'hooks': hooks}),
          harness: harness,
        ),
      );
    }

    return TranslationResult(changes: changes, notes: notes);
  }

  /// Renders an agent role. Codex requires `name` and `developer_instructions`,
  /// and drops with a warning any role that declares no `description`, so all
  /// three are written.
  ///
  /// Serialized by `TomlDocument` rather than hand-escaped: an agent body is a
  /// whole markdown document, full of quotes, backticks and backslashes.
  String _agent(AgentAsset agent, String skillsRoot) => TomlDocument.fromMap({
    'name': agent.name,
    'description': agent.description,
    'developer_instructions': renderAgentBody(agent, skillsRoot: skillsRoot),
  }).toString();
}
