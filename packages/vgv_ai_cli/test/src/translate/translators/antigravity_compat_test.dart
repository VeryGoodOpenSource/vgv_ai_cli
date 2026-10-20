import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [antigravityPreamble] and [antigravityCompatScript] for real,
/// through bash and jq, on top of a stub script that records every payload
/// it is handed. Skipped where bash or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Antigravity compat script', () {
    late Directory temp;
    late Directory pluginRoot;
    late File compat;
    late File script;
    late File log;

    setUp(() {
      temp = const LocalFileSystem().systemTempDirectory.createTempSync();
      addTearDown(() => temp.deleteSync(recursive: true));
      // A space and a quote, since the root is spliced into the script.
      pluginRoot = temp.childDirectory("it's a plugin")..createSync();
      log = temp.childFile('log');
      script = temp.childFile('hook.sh');
      compat = temp.childFile(AntigravityTranslator.compatScript)
        ..writeAsStringSync(antigravityCompatScript);
      final preamble = antigravityPreamble
          .replaceAll('__ROOT__', '"${pluginRoot.path}"')
          .replaceAll('__COMPAT__', '"${compat.path}"');
      script.writeAsStringSync(
        '#!/bin/bash\n$preamble'
        // A stub plugin script: records the root and payload, answers and
        // exits as told.
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

    /// Runs the script on [payload] for [event], returning its exit code,
    /// stdout and stderr.
    Future<(int, String, String)> run(
      Map<String, Object?> payload, {
      String event = 'PreToolUse',
      Map<String, String> env = const {},
      bool direct = false,
      String? path,
    }) async {
      final process = await Process.start(
        direct ? script.path : 'bash',
        direct ? const [] : [script.path],
        environment: {
          'LOG': log.path,
          'VGV_HOOK_EVENT': event,
          'PATH': ?path,
          ...env,
        },
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

    /// What Antigravity sends for a tool call.
    Map<String, Object?> call(String tool, Map<String, Object?> args) => {
      'toolCall': {'name': tool, 'args': args},
      'stepIdx': 3,
      'conversationId': 'c1',
      'workspacePaths': [temp.path],
      'transcriptPath': '${temp.path}/transcript.jsonl',
      'modelName': 'gemini',
    };

    test('hands the script a shell command as Claude Code names it', () async {
      await run(call('run_command', {'CommandLine': 'dart test', 'Cwd': '/'}));

      final payload = runs().single.$2;
      expect(payload['hook_event_name'], 'PreToolUse');
      expect(payload['tool_name'], 'Bash');
      expect(payload['tool_input'], containsPair('command', 'dart test'));
      expect(payload['cwd'], temp.path);
      expect(payload['session_id'], 'c1');
    });

    test(
      'hands the script an edit, a write and a read under file_path',
      () async {
        await run(
          call('replace_file_content', {'TargetFile': '/a.dart'}),
          event: 'PostToolUse',
        );
        await run(call('write_to_file', {'TargetFile': '/b.dart'}));
        await run(call('view_file', {'AbsolutePath': '/c.dart'}));

        expect(runs().map((r) => r.$2['tool_name']), ['Edit', 'Write', 'Read']);
        expect(runs().map((r) => r.$2['tool_input']), [
          containsPair('file_path', '/a.dart'),
          containsPair('file_path', '/b.dart'),
          containsPair('file_path', '/c.dart'),
        ]);
        expect(runs().first.$2['hook_event_name'], 'PostToolUse');
      },
    );

    test('hands the script an MCP call as Claude Code names it', () async {
      await run(
        call('call_mcp_tool', {
          'ServerName': 'vgv_very-good-cli',
          'ToolName': 'test',
          'Arguments': {'directory': '/app'},
        }),
      );

      final payload = runs().single.$2;
      expect(payload['tool_name'], 'mcp__vgv_very-good-cli__test');
      expect(payload['tool_input'], {'directory': '/app'});
    });

    test('passes an unknown tool and its args through', () async {
      await run(call('mcp_very_good_cli_test', {'x': 1}));

      final payload = runs().single.$2;
      expect(payload['tool_name'], 'mcp_very_good_cli_test');
      expect(payload['tool_input'], {'x': 1});
    });

    test('hands the script the plugin root, quoted as it was', () async {
      await run(call('run_command', {'CommandLine': 'ls'}));

      expect(runs().single.$1, pluginRoot.path);
    });

    test('lifts a permission decision to where Antigravity reads it', () async {
      final (code, out, _) = await run(
        call('run_command', {'CommandLine': 'dart test'}),
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

    test('turns a denial on stderr before a tool into a decision', () async {
      final (code, out, err) = await run(
        call('run_command', {'CommandLine': 'dart test'}),
        env: {'EXIT': '2', 'COMPLAINT': 'use the MCP tool'},
      );

      expect(code, 0);
      expect(jsonDecode(out), {
        'decision': 'deny',
        'reason': 'use the MCP tool',
      });
      expect(err, 'use the MCP tool\n');
    });

    test('prints nothing before a tool when the script says nothing', () async {
      final (code, out, _) = await run(
        call('run_command', {'CommandLine': 'ls'}),
      );

      expect(code, 0);
      expect(out, isEmpty);
    });

    test(
      'answers an empty object after a tool, whatever the script said',
      () async {
        final (code, out, err) = await run(
          call('replace_file_content', {'TargetFile': '/a.dart'}),
          event: 'PostToolUse',
          env: {'EXIT': '2', 'COMPLAINT': '1 issue found.', 'ANSWER': 'x'},
        );

        expect(code, 0);
        expect(out, '{}\n');
        expect(err, '1 issue found.\n');
      },
    );

    test('hands a session-start message to the agent as a step', () async {
      final (_, out, _) = await run(
        {
          'conversationId': 'c1',
          'workspacePaths': [temp.path],
        },
        event: 'SessionStart',
        env: {'ANSWER': 'Very Good CLI is not installed.'},
      );

      expect(jsonDecode(out), {
        'injectSteps': [
          {'systemMessage': 'Very Good CLI is not installed.'},
        ],
      });
    });

    test('prints what the script says on any other event as it came', () async {
      final (_, out, _) = await run(
        {'conversationId': 'c1'},
        event: 'Stop',
        env: {'ANSWER': '{"a":1}'},
      );

      expect(out, '{"a":1}\n');
    });

    test('passes the payload and the answer as they are without jq', () async {
      final bin = temp.childDirectory('bin')..createSync();
      for (final tool in ['bash', 'cat', 'mktemp', 'rm']) {
        final found = Process.runSync('bash', ['-c', 'command -v $tool']);
        bin.childLink(tool).createSync((found.stdout as String).trim());
      }
      final payload = call('run_command', {'CommandLine': 'ls'});

      final (code, out, _) = await run(
        payload,
        path: bin.path,
        env: {'EXIT': '2', 'ANSWER': 'plain'},
      );

      expect(code, 0);
      expect(out, 'plain\n');
      expect(runs().single.$2, payload);
    });

    test('re-runs itself when the script is executed directly', () async {
      await run(call('run_command', {'CommandLine': 'ls'}), direct: true);

      expect(runs().single.$2['tool_name'], 'Bash');
    });
  }, skip: bash ? null : 'needs bash and jq on PATH');
}
