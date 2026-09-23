import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/agent_markdown.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_tool_map.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';
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
      path: StagedPaths.openCodeConfig,
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
              '${McpToolMap.rewrite(skill.body)}',
          harness: harness,
        ),
      );
    }

    changes.addAll(_hooks(assets, home: home, root: root, notes: notes));

    return TranslationResult(changes: changes, notes: notes);
  }

  /// Translates what OpenCode's experimental hooks can express.
  ///
  /// Config-level hooks are limited to `file_edited` and `session_completed`,
  /// so a post-edit hook maps and everything else, a pre-tool guard included,
  /// has no equivalent at all. OpenCode keys on a file glob rather than a tool
  /// name, so the matcher is not translated so much as replaced.
  Iterable<PlannedChange> _hooks(
    PluginAssets assets, {
    required Directory home,
    required String root,
    required List<TranslationNote> notes,
  }) sync* {
    final commands = <Map<String, Object?>>[];

    for (final hook in assets.hooks) {
      if (hook.event != 'PostToolUse') {
        notes.add(
          TranslationNote(
            subject: '${hook.event} hook from ${hook.plugin}',
            reason:
                'OpenCode config hooks cover only file_edited and '
                'session_completed',
          ),
        );
        continue;
      }

      for (final command in hook.commands) {
        if (command.type != 'command') {
          notes.add(
            TranslationNote(
              subject: '${hook.event} hook from ${hook.plugin}',
              reason: 'a ${command.type} command has no OpenCode equivalent',
            ),
          );
          continue;
        }
        if (command.timeout != null) {
          notes.add(
            TranslationNote(
              subject: '${hook.event} hook from ${hook.plugin}',
              reason:
                  'OpenCode config hooks take no timeout, so its '
                  '${command.timeout}s limit was dropped',
            ),
          );
        }

        commands.add({
          'command': [
            'bash',
            '-c',
            resolveHookCommand(command, home: home, plugin: hook.plugin),
          ],
        });
      }
    }

    if (commands.isEmpty) return;

    yield PlannedChange.mergeJson(
      file: home.fileSystem.file(p.join(root, 'opencode.json')),
      contents: jsonEncode({
        'experimental': {
          'hook': {
            // Claude matches on tool name and OpenCode on a file glob, so an
            // Edit|Write matcher becomes every file rather than a translation.
            'file_edited': {'*': commands},
          },
        },
      }),
      harness: harness,
    );
  }
}
