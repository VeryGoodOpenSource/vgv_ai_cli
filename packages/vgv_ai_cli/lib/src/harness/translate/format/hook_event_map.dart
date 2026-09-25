import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';

/// One hook rendered into the nested shape Claude, Codex and Gemini share.
typedef HookRegistrations = Map<String, List<Map<String, Object?>>>;

/// Builds the `hooks` document Codex and Gemini both read.
///
/// The two differ only in their [HookVocabulary], so one builder serves both.
HookRegistrations buildHookDocument(
  List<HookAsset> hooks, {
  required Directory home,
  required HookVocabulary vocabulary,
  required List<TranslationNote> notes,
}) {
  final document = <String, List<Map<String, Object?>>>{};

  for (final hook in hooks) {
    final event = vocabulary.events[hook.event];
    if (event == null) {
      notes.add(
        TranslationNote(
          subject: '${hook.event} hook from ${hook.plugin}',
          reason: '${vocabulary.displayName} has no equivalent lifecycle event',
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
            reason:
                'a ${command.type} command has no '
                '${vocabulary.displayName} equivalent',
          ),
        );
        continue;
      }

      commands.add({
        'type': 'command',
        'command': resolveHookCommand(command, home: home, plugin: hook.plugin),
        if (command.timeout != null)
          'timeout': command.timeout! * vocabulary.timeoutScale,
      });
    }

    if (commands.isEmpty) continue;

    document.putIfAbsent(event, () => []).add({
      if (hook.matcher != null)
        'matcher': rewriteMatcher(
          hook.matcher!,
          vocabulary: vocabulary,
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
/// A matcher is a regex alternation, so each alternative is mapped on its own.
/// An alternative with no counterpart is kept verbatim and reported: dropping
/// it would silently widen the matcher to every tool.
String rewriteMatcher(
  String matcher, {
  required HookVocabulary vocabulary,
  required String plugin,
  required List<TranslationNote> notes,
}) {
  final tools = vocabulary.tools;
  if (tools == null) return matcher;

  return matcher
      .split('|')
      .map((alternative) {
        final mapped = tools[alternative];
        if (mapped != null) return mapped;

        notes.add(
          TranslationNote(
            subject: 'matcher `$alternative` from $plugin',
            reason:
                '${vocabulary.displayName} names that tool differently, so the '
                'matcher was kept as written and may not fire',
          ),
        );
        return alternative;
      })
      .join('|');
}

/// {@template hook_vocabulary}
/// How one harness names the hook concepts Claude also names.
/// {@endtemplate}
enum HookVocabulary {
  /// Gemini renames the events and the tools, and counts timeouts in
  /// milliseconds.
  gemini(
    displayName: 'Gemini',
    timeoutScale: 1000,
    events: {
      'PreToolUse': 'BeforeTool',
      'PostToolUse': 'AfterTool',
      'SessionStart': 'SessionStart',
    },
    tools: {
      'Read': 'read_file',
      'Glob': 'glob',
      'Grep': 'search_file_content',
      'Edit': 'replace',
      'Write': 'write_file',
      'Bash': 'run_shell_command',
    },
  ),

  /// Codex uses Claude's names throughout, so it maps no tools at all.
  ///
  /// Only the three events the pinned plugins ship. Listing the rest would be
  /// an untested claim about another project's API, and an event with no entry
  /// already produces a note rather than being dropped.
  codex(
    displayName: 'Codex',
    timeoutScale: 1,
    events: {
      'PreToolUse': 'PreToolUse',
      'PostToolUse': 'PostToolUse',
      'SessionStart': 'SessionStart',
    },
  );

  /// {@macro hook_vocabulary}
  new({
    required this.displayName,
    required this.timeoutScale,
    required this.events,
    this.tools,
  });

  /// The harness's name, for reporting.
  final String displayName;

  /// What to multiply Claude's seconds by.
  final int timeoutScale;

  /// This harness's event names, keyed by Claude's.
  final Map<String, String> events;

  /// This harness's tool names, keyed by Claude's.
  ///
  /// Null when the harness uses Claude's names, so a matcher passes through
  /// untouched. An identity table instead would report every name it forgot,
  /// including the regex matchers the plugins actually ship.
  final Map<String, String>? tools;
}
