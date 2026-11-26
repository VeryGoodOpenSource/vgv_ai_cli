import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [devinPreamble] and [devinCompatScript] for real, through bash and
/// jq, on top of a stub script that records every payload it is handed.
/// Skipped where bash or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Devin compat script', () {
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
      compat = temp.childFile(DevinTranslator.compatScript)
        ..writeAsStringSync(devinCompatScript);
      final preamble = devinPreamble
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

    /// What Devin sends for a tool call.
    Map<String, Object?> call(
      String tool,
      Map<String, Object?> input, {
      String event = 'PreToolUse',
    }) => {
      'hook_event_name': event,
      'tool_name': tool,
      'tool_input': input,
      'session_id': 's1',
      'prompt_id': 'p1',
    };

    test('hands the script the plugin root it was copied from', () async {
      await run(call('exec', {'command': 'dart test'}));

      expect(runs().single.$1, pluginRoot.path);
    });

    test('renames each built-in tool to the one Claude Code names', () async {
      for (final tool in ['exec', 'edit', 'apply_patch', 'write', 'read']) {
        await run(call(tool, const {}));
      }

      expect(runs().map((r) => r.$2['tool_name']), [
        'Bash',
        'Edit',
        'Edit',
        'Write',
        'Read',
      ]);
    });

    test('leaves an MCP tool name and the rest of the payload alone', () async {
      final payload = call('mcp__very-good-cli__test', {'dart': true});

      await run(payload);

      expect(runs().single.$2, payload);
    });

    test('leaves a payload that names no tool alone', () async {
      final payload = {'hook_event_name': 'SessionStart', 'source': 'startup'};

      await run(payload);

      expect(runs().single.$2, payload);
    });

    test('answers a deny as the decision Devin reads', () async {
      final (code, out, _) = await run(
        call('exec', {'command': 'dart test'}),
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
        'decision': 'block',
        'reason': 'use the MCP tool',
      });
    });

    test('answers an allow as the decision Devin reads', () async {
      final (_, out, _) = await run(
        call('mcp__very-good-cli__test', const {}),
        env: {
          'ANSWER': jsonEncode({
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'allow',
              'permissionDecisionReason': 'verified',
            },
          }),
        },
      );

      expect(jsonDecode(out), {'decision': 'approve', 'reason': 'verified'});
    });

    test("says nothing for an ask, so Devin's own prompt runs", () async {
      final (code, out, _) = await run(
        call('exec', const {}),
        env: {
          'ANSWER': jsonEncode({
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'ask',
            },
          }),
        },
      );

      expect(code, 0);
      expect(out, isEmpty);
    });

    test('passes other JSON the script prints through as it came', () async {
      final answer = {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'additionalContext': 'try the wingspan plugin',
        },
      };

      final (_, out, _) = await run(
        call('read', {'file_path': '/a.dart'}),
        env: {'ANSWER': jsonEncode(answer)},
      );

      expect(jsonDecode(out), answer);
    });

    test('wraps a session-start line as the context Devin injects', () async {
      final (_, out, _) = await run(
        {'hook_event_name': 'SessionStart', 'source': 'startup'},
        env: {'ANSWER': 'Very Good CLI is not installed.'},
      );

      expect(jsonDecode(out), {
        'hookSpecificOutput': {
          'hookEventName': 'SessionStart',
          'additionalContext': 'Very Good CLI is not installed.',
        },
      });
    });

    test('prints a line on an event that injects none as it came', () async {
      final (_, out, _) = await run(
        call('exec', const {}),
        env: {'ANSWER': 'a bare line'},
      );

      expect(out, 'a bare line\n');
    });

    test('blocks a tool on an exit 2, with what the script said', () async {
      final (code, out, err) = await run(
        call('exec', {'command': 'dart test'}),
        env: {'EXIT': '2', 'COMPLAINT': 'run it through the MCP tool'},
      );

      expect(code, 2);
      expect(err, 'run it through the MCP tool\n');
      expect(jsonDecode(out), {
        'decision': 'block',
        'reason': 'run it through the MCP tool',
      });
    });

    test('turns an exit 2 after a tool into context, not a block', () async {
      final (code, out, _) = await run(
        call('edit', {'file_path': '/a.dart'}, event: 'PostToolUse'),
        env: {'EXIT': '2', 'COMPLAINT': 'error - a.dart:1:1 - unused import'},
      );

      expect(code, 0);
      expect(jsonDecode(out), {
        'hookSpecificOutput': {
          'hookEventName': 'PostToolUse',
          'additionalContext': 'error - a.dart:1:1 - unused import',
        },
      });
    });

    test('lets an exit 2 on an event Devin injects nothing on stand', () async {
      final (code, out, _) = await run(
        {'hook_event_name': 'Stop'},
        env: {'EXIT': '2', 'COMPLAINT': 'run the tests first'},
      );

      expect(code, 2);
      expect(out, isEmpty);
    });

    test('lets any other failing exit through, as Claude Code does', () async {
      final (code, _, err) = await run(
        call('exec', const {}),
        env: {'EXIT': '1', 'COMPLAINT': 'jq is required'},
      );

      expect(code, 1);
      expect(err, 'jq is required\n');
    });

    test('passes the payload and the answer as they are without jq', () async {
      final bin = temp.childDirectory('bin')..createSync();
      for (final tool in ['bash', 'cat', 'mktemp', 'rm']) {
        final found = Process.runSync('bash', ['-c', 'command -v $tool']);
        bin.childLink(tool).createSync((found.stdout as String).trim());
      }
      final payload = call('exec', {'command': 'ls'});

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
      await run(call('exec', {'command': 'ls'}), direct: true);

      expect(runs().single.$2['tool_name'], 'Bash');
    });
  }, skip: bash ? null : 'needs bash and jq on PATH');
}
