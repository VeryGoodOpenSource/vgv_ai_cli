import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/format.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template opencode_translator}
/// Configures OpenCode.
///
/// Agents and commands are both markdown with frontmatter; an agent is marked
/// `mode: subagent` so it is delegated to rather than driven directly. The
/// loader accepts both `agent/` and `agents/`, and the singular form is what
/// the maintainers use themselves.
/// {@endtemplate}
class const OpenCodeTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.opencode;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = p.join(home.path, '.config', 'opencode');
    final fs = home.fileSystem;
    final skillsRoot = agentsSkillsRoot(home).path;
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    final config = stagedContents(
      staged: staged,
      fragment: StagedFragment.openCodeConfig,
      target: fs.file(p.join(root, 'opencode.json')),
      notes: notes,
    );
    if (config != null) {
      changes.add(
        PlannedChange.mergeJson(
          file: fs.file(p.join(root, 'opencode.json')),
          contents: config,
          harness: harness,
        ),
      );
    }

    for (final agent in assets.agents) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'agent', '${agent.name}.md')),
          contents: renderAgent(agent, {
            'description': agent.description,
            'mode': 'subagent',
          }, skillsRoot: skillsRoot),
          harness: harness,
        ),
      );
    }

    for (final skill in assets.invocableSkills) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'command', '${skill.name}.md')),
          contents:
              '${Frontmatter.render({'description': skill.description})}\n'
              '${skill.body}',
          harness: harness,
        ),
      );
    }

    return TranslationResult(
      changes: changes,
      notes: [...notes, ...hooksNotes(assets)],
    );
  }
}
