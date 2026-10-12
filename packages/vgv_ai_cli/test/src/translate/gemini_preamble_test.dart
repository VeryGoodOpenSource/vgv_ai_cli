import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [GeminiTranslator.preamble] for real, through bash and jq, on top of
/// a stub script that records every payload it is handed.
///
/// The Dart suite otherwise asserts only where the preamble is placed, and a
/// shell program that decides what a guard sees and whether its denial
/// reaches Gemini deserves to be executed. Skipped where bash or jq is
/// missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Gemini preamble', () {
    late Directory temp;
    late Directory pluginRoot;
    late File script;
    late File log;

    setUp(() {
      temp = const LocalFileSystem().systemTempDirectory.createTempSync();
      addTearDown(() => temp.deleteSync(recursive: true));
      // A space and a quote, since the root is spliced into the script.
      pluginRoot = temp.childDirectory("it's a plugin")..createSync();
      log = temp.childFile('log');
      script = temp.childFile('hook.sh');
      final preamble = GeminiTranslator.preamble.replaceAll(
        '__ROOT__',
        '"${pluginRoot.path}"',
      );
      script.writeAsStringSync(
        '#!/bin/bash\n$preamble'
        // What a plugin script would do: read the payload once, act on it.
        // This one records the root it sees and the payload, answers when
        // asked to, and exits as it is told to.
        r'''
input=$(cat)
printf '%s\x1f%s\x1e' "$CLAUDE_PLUGIN_ROOT" "$input" >> "$LOG"
[ -z "${ANSWER:-}" ] || printf '%s\n' "$ANSWER"
[ -z "${COMPLAINT:-}" ] || printf '%s\n' "$COMPLAINT" >&2
exit "${EXIT:-0}"
''',
      );
      Process.runSync('chmod', ['755', script.path]);
    });

    /// Runs the script on [payload], returning its exit code, stdout and
    /// stderr.
    Future<(int, String, String)> run(
      Map<String, Object?> payload, {
      Map<String, String> env = const {},
      bool direct = false,
      String? path,
    }) async {
      final process = await Process.start(
        direct ? script.path : 'bash',
        direct ? const [] : [script.path],
        environment: {'LOG': log.path, 'PATH': ?path, ...env},
        includeParentEnvironment: path == null,
      );
      process.stdin.write(jsonEncode(payload));
      await process.stdin.close();
      final out = process.stdout.transform(utf8.decoder).join();
      final err = process.stderr.transform(utf8.decoder).join();
      return (await process.exitCode, await out, await err);
    }

    /// Each run the script saw: the root it was given and its payload.
    List<(String, Map<String, Object?>)> runs() => [
      for (final record in log.readAsStringSync().split('\x1e'))
        if (record.isNotEmpty)
          switch (record.split('\x1f')) {
            [final root, final payload] => (
              root,
              jsonDecode(payload) as Map<String, Object?>,
            ),
            _ => throw StateError('malformed record: $record'),
          },
    ];

    /// What Gemini sends after an edit: its own event and tool names over
    /// the same argument keys Claude Code uses.
    Map<String, Object?> edit(String file) => {
      'hook_event_name': 'AfterTool',
      'cwd': temp.path,
      'tool_name': 'replace',
      'tool_input': {'file_path': file, 'old_string': 'a', 'new_string': 'b'},
    };

    /// What Gemini sends before a shell command.
    Map<String, Object?> shell(String command) => {
      'hook_event_name': 'BeforeTool',
      'cwd': temp.path,
      'tool_name': 'run_shell_command',
      'tool_input': {'command': command},
    };

    test('names the event and the tool as Claude Code does', () async {
      await run(edit('${temp.path}/a.dart'));
      await run(shell('ls'));

      expect(runs().map((r) => r.$2['hook_event_name']), [
        'PostToolUse',
        'PreToolUse',
      ]);
      expect(runs().map((r) => r.$2['tool_name']), ['Edit', 'Bash']);
      expect(
        (runs().first.$2['tool_input']! as Map)['file_path'],
        '${temp.path}/a.dart',
      );
    });

    test("gives an MCP tool Claude Code's prefix", () async {
      await run({
        'hook_event_name': 'BeforeTool',
        'tool_name': 'mcp_very-good-cli_test',
        'tool_input': <String, Object?>{},
      });

      expect(runs().single.$2['tool_name'], 'mcp__very-good-cli_test');
    });

    test("passes Claude Code's own payload through as it came", () async {
      final payload = {
        'hook_event_name': 'PostToolUse',
        'tool_name': 'Edit',
        'tool_input': {'file_path': '${temp.path}/a.dart'},
      };

      await run(payload);

      expect(runs().single.$2, payload);
    });

    test('hands the script the plugin root, quoted as it was', () async {
      await run(edit('${temp.path}/a.dart'));

      expect(runs().single.$1, pluginRoot.path);
    });

    test('lifts a permission decision to where Gemini reads it', () async {
      final (code, out, _) = await run(
        shell('dart test'),
        env: {
          'ANSWER': jsonEncode({
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'deny',
              'permissionDecisionReason': 'use the MCP tool',
            },
          }),
        },
      );

      expect(code, 0);
      expect(jsonDecode(out), {
        'decision': 'deny',
        'reason': 'use the MCP tool',
      });
    });

    test('lifts an approval the same way', () async {
      final (_, out, _) = await run(
        shell('very_good test'),
        env: {
          'ANSWER': jsonEncode({
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'allow',
            },
          }),
        },
      );

      expect(jsonDecode(out), {'decision': 'allow'});
    });

    test('prints any other answer as it came', () async {
      final (_, out, _) = await run(
        shell('ls'),
        env: {'ANSWER': '{"decision":"block"}'},
      );

      expect(out, '{"decision":"block"}\n');
    });

    test('hands a session-start message to the agent as context', () async {
      final (_, out, _) = await run(
        {'hook_event_name': 'SessionStart', 'cwd': temp.path},
        env: {'ANSWER': 'Very Good CLI is not installed.'},
      );

      expect(jsonDecode(out), {
        'hookSpecificOutput': {
          'additionalContext': 'Very Good CLI is not installed.',
        },
      });
    });

    test('prints nothing when the script prints nothing', () async {
      final (_, out, _) = await run(edit('${temp.path}/a.dart'));

      expect(out, isEmpty);
    });

    test('leaves a denial before a tool as it is, stderr and all', () async {
      // Gemini reads an exit 2 before a tool as Claude Code does: the tool is
      // denied and stderr is the reason.
      final (code, out, err) = await run(
        shell('dart test'),
        env: {'EXIT': '2', 'COMPLAINT': 'use the MCP tool'},
      );

      expect(code, 2);
      expect(out, isEmpty);
      expect(err, 'use the MCP tool\n');
    });

    test('turns a complaint on stderr after a tool into context', () async {
      // Gemini would hide the tool's result behind the complaint, where
      // Claude Code hands the agent both.
      final (code, out, err) = await run(
        edit('${temp.path}/a.dart'),
        env: {'EXIT': '2', 'COMPLAINT': '1 issue found.'},
      );

      expect(code, 0);
      expect(jsonDecode(out), {
        'hookSpecificOutput': {'additionalContext': '1 issue found.'},
      });
      expect(err, '1 issue found.\n');
    });

    test('lets any other failure through as it is', () async {
      final (code, _, err) = await run(
        edit('${temp.path}/a.dart'),
        env: {'EXIT': '1', 'COMPLAINT': 'jq not found'},
      );

      expect(code, 1);
      expect(err, 'jq not found\n');
    });

    test('leaves an exit 2 with an answer as it is', () async {
      final (code, out, _) = await run(
        edit('${temp.path}/a.dart'),
        env: {'EXIT': '2', 'ANSWER': '{"a":1}', 'COMPLAINT': 'ignored'},
      );

      expect(code, 2);
      expect(out, '{"a":1}\n');
    });

    test('passes the payload and the answer as they are without jq', () async {
      final bin = temp.childDirectory('bin')..createSync();
      for (final tool in ['bash', 'cat', 'mktemp', 'rm']) {
        final found = Process.runSync('bash', ['-c', 'command -v $tool']);
        bin.childLink(tool).createSync((found.stdout as String).trim());
      }
      final payload = edit('${temp.path}/a.dart');

      final (code, out, _) = await run(
        payload,
        path: bin.path,
        env: {'EXIT': '2', 'ANSWER': 'plain'},
      );

      expect(code, 2);
      expect(out, 'plain\n');
      expect(runs().single.$2, payload);
    });

    test('re-runs itself when the script is executed directly', () async {
      await run(edit('${temp.path}/a.dart'), direct: true);

      expect(runs().single.$2['tool_name'], 'Edit');
    });
  }, skip: bash ? null : 'needs bash and jq on PATH');
}
