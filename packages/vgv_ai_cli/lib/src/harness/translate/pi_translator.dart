import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/agent_markdown.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/skills_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template pi_translator}
/// Configures Pi.
///
/// Pi reads `~/.agents/skills` natively and has no subagent primitive, so an
/// agent becomes a prompt the user invokes directly. Its MCP-backed tools are
/// already rewritten to CLI commands in the shared skills copy, because Pi
/// supports no MCP at all.
/// {@endtemplate}
class const PiTranslator() extends HarnessTranslator {
  /// Distinguishes a prompt that was an agent from one that was a command.
  ///
  /// Pi is the only harness where both land in one directory, so without a
  /// prefix an agent and a command sharing a name would overwrite each other
  /// and the last change applied would silently win.
  static const agentPrefix = 'agent-';

  @override
  Harness get harness => Harness.pi;

  @override
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = p.join(home.path, '.pi', 'agent');
    final fs = home.fileSystem;
    final skillsRoot = agentsSkillsRoot(home).path;
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    final settings = stagedContents(
      staged: staged,
      path: StagedPaths.piSettings,
      target: fs.file(p.join(root, 'settings.json')),
      notes: notes,
    );
    if (settings != null) {
      changes.add(
        PlannedChange.mergeJson(
          file: fs.file(p.join(root, 'settings.json')),
          contents: settings,
          harness: harness,
        ),
      );
    }

    for (final agent in assets.agents) {
      notes.add(
        TranslationNote(
          subject: 'agent ${agent.name}',
          reason:
              'Pi has no subagent primitive, so it is written as a prompt '
              'the user invokes directly',
        ),
      );
      changes.add(
        PlannedChange.own(
          file: fs.file(
            p.join(root, 'prompts', '$agentPrefix${agent.name}.md'),
          ),
          contents: renderAgentBody(agent, skillsRoot: skillsRoot),
          harness: harness,
        ),
      );
    }

    for (final skill in assets.skills.where((s) => s.userInvocable)) {
      changes.add(
        PlannedChange.own(
          file: fs.file(p.join(root, 'prompts', '${skill.name}.md')),
          contents: skill.body,
          harness: harness,
        ),
      );
    }

    for (final hook in assets.hooks) {
      notes.add(
        TranslationNote(
          subject: '${hook.event} hook from ${hook.plugin}',
          reason:
              'Pi has no declarative hooks; its extensions are TypeScript '
              'modules, so this was not translated',
        ),
      );
    }

    return TranslationResult(changes: changes, notes: notes);
  }
}
