import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/hook_staging.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';

/// One hook rendered into the nested shape Claude, Codex and Gemini share.
typedef HookRegistrations = Map<String, List<Map<String, Object?>>>;

/// Builds the `hooks` document Codex and Gemini both read.
///
/// The two differ only in what they call each event, what they call each tool,
/// and whether a timeout is seconds or milliseconds, so one builder serves
/// both and the differences arrive as arguments.
HookRegistrations buildHookDocument(
  List<HookAsset> hooks, {
  required Directory home,
  required Map<String, String> events,
  required Map<String, String> tools,
  required int timeoutScale,
  required String harnessName,
  required List<TranslationNote> notes,
}) {
  final document = <String, List<Map<String, Object?>>>{};

  for (final hook in hooks) {
    final event = events[hook.event];
    if (event == null) {
      notes.add(
        TranslationNote(
          subject: '${hook.event} hook from ${hook.plugin}',
          reason: '$harnessName has no equivalent lifecycle event',
        ),
      );
      continue;
    }

    final commands = <Map<String, Object?>>[];
    for (final command in hook.commands) {
      // `type: prompt` is Claude asking the model something, not a process to
      // run. Nowhere else models it, and running the text as a shell command
      // would be worse than not running it.
      if (command.type != 'command') {
        notes.add(
          TranslationNote(
            subject: '${hook.event} hook from ${hook.plugin}',
            reason: 'a ${command.type} command has no $harnessName equivalent',
          ),
        );
        continue;
      }

      commands.add({
        'type': 'command',
        'command': resolveHookCommand(command, home: home, plugin: hook.plugin),
        if (command.timeout != null) 'timeout': command.timeout! * timeoutScale,
      });
    }

    if (commands.isEmpty) continue;

    document.putIfAbsent(event, () => []).add({
      if (hook.matcher != null)
        'matcher': rewriteMatcher(
          hook.matcher!,
          tools: tools,
          harnessName: harnessName,
          plugin: hook.plugin,
          notes: notes,
        ),
      'hooks': commands,
    });
  }

  return document;
}

/// Rewrites a Claude tool matcher into another harness's tool names.
///
/// A matcher is a regex alternation over tool names, so each alternative is
/// mapped on its own. An alternative with no counterpart is kept verbatim and
/// reported: dropping it would silently widen the matcher to every tool.
String rewriteMatcher(
  String matcher, {
  required Map<String, String> tools,
  required String harnessName,
  required String plugin,
  required List<TranslationNote> notes,
}) => matcher
    .split('|')
    .map((alternative) {
      final mapped = tools[alternative];
      if (mapped != null) return mapped;

      notes.add(
        TranslationNote(
          subject: 'matcher `$alternative` from $plugin',
          reason:
              '$harnessName names that tool differently, so the matcher '
              'was kept as written and may not fire',
        ),
      );
      return alternative;
    })
    .join('|');

/// Gemini's lifecycle events, keyed by Claude's name for the same point.
const geminiEvents = <String, String>{
  'PreToolUse': 'BeforeTool',
  'PostToolUse': 'AfterTool',
  'SessionStart': 'SessionStart',
  'SessionEnd': 'SessionEnd',
};

/// Gemini's tool names, keyed by Claude's.
const geminiTools = <String, String>{
  'Read': 'read_file',
  'Glob': 'glob',
  'Grep': 'search_file_content',
  'Edit': 'replace',
  'Write': 'write_file',
  'Bash': 'run_shell_command',
};

/// Codex's lifecycle events, which carry Claude's names unchanged.
const codexEvents = <String, String>{
  'PreToolUse': 'PreToolUse',
  'PostToolUse': 'PostToolUse',
  'SessionStart': 'SessionStart',
  'SessionEnd': 'SessionEnd',
  'UserPromptSubmit': 'UserPromptSubmit',
  'Stop': 'Stop',
};

/// Codex's tool names, which are Claude's.
const codexTools = <String, String>{
  'Read': 'Read',
  'Glob': 'Glob',
  'Grep': 'Grep',
  'Edit': 'Edit',
  'Write': 'Write',
  'Bash': 'Bash',
};
