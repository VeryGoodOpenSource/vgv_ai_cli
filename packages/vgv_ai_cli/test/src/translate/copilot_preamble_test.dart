import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [CopilotTranslator.preamble] for real, through bash and jq, on top of
/// a stub script that records every payload it is handed. Skipped where bash
/// or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Copilot preamble', () {
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
      final preamble = CopilotTranslator.preamble.replaceAll(
        '__ROOT__',
        '"${pluginRoot.path}"',
      );
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

    /// What Copilot sends for an edit: Claude Code's tool name over its own
    /// argument keys.
    Map<String, Object?> edit(String file) => {
      'hook_event_name': 'PostToolUse',
      'cwd': temp.path,
      'tool_name': 'Edit',
      'tool_input': {'path': file, 'old_str': 'a', 'new_str': 'b'},
    };

    /// What Copilot sends for a patch: Claude Code's tool name over the
    /// patch text itself.
    Map<String, Object?> patch(List<String> lines, {String? cwd}) => {
      'hook_event_name': 'PostToolUse',
      'cwd': cwd ?? temp.path,
      'tool_name': 'Edit',
      'tool_input': ['*** Begin Patch', ...lines, '*** End Patch'].join('\n'),
    };

    test('runs the script once per file of a patch that is on disk', () async {
      temp.childFile('old.dart').writeAsStringSync('');
      temp.childFile('renamed.dart').writeAsStringSync('');
      temp.childDirectory('lib').createSync();
      temp.childFile('lib/added.dart').writeAsStringSync('');

      final (code, _, _) = await run(
        patch([
          '*** Update File: old.dart',
          '*** Delete File: gone.dart',
          '*** Update File: was.dart',
          '*** Move to: renamed.dart',
          '*** Add File: ${temp.path}/lib/added.dart',
          '*** Add File: lib/not_yet.dart',
        ]),
      );

      expect(code, 0);
      expect(
        [
          for (final (_, payload) in runs())
            [
              payload['tool_name'],
              (payload['tool_input']! as Map)['file_path'],
            ].join(' '),
        ],
        [
          'Edit ${temp.path}/old.dart',
          'Edit ${temp.path}/renamed.dart',
          'Write ${temp.path}/lib/added.dart',
        ],
      );
    });

    test(
      'joins what every file of a patch says, and fails on the first',
      () async {
        temp.childFile('a.dart').writeAsStringSync('');
        temp.childFile('b.dart').writeAsStringSync('');

        final (code, out, _) = await run(
          patch(['*** Update File: a.dart', '*** Update File: b.dart']),
          env: {'EXIT': '2', 'COMPLAINT': 'issue'},
        );

        expect(code, 0);
        expect(jsonDecode(out), {'additionalContext': 'issue\nissue'});
        expect(runs(), hasLength(2));
      },
    );

    test('passes a patch naming no file on disk through as it came', () async {
      final payload = patch(['*** Add File: not_yet.dart']);

      await run(payload);

      expect(runs().single.$2, payload);
    });

    test('names the edited file under file_path as well', () async {
      await run(edit('${temp.path}/a.dart'));

      final input = runs().single.$2['tool_input']! as Map;
      expect(input['file_path'], '${temp.path}/a.dart');
      expect(input['path'], '${temp.path}/a.dart');
    });

    test("passes Claude Code's own payload through as it came", () async {
      final payload = {
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

    test('lifts a permission decision to where Copilot reads it', () async {
      final (code, out, _) = await run(
        {
          'tool_name': 'Bash',
          'tool_input': {'command': 'dart test'},
        },
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
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'use the MCP tool',
      });
    });

    test('prints any other answer as it came', () async {
      final (_, out, _) = await run(
        {
          'tool_name': 'Bash',
          'tool_input': {'command': 'ls'},
        },
        env: {'ANSWER': '{"decision":"block"}'},
      );

      expect(out, '{"decision":"block"}\n');
    });

    test('wraps a session-start message as context', () async {
      final (_, out, _) = await run(
        {'hook_event_name': 'SessionStart', 'cwd': temp.path},
        env: {'ANSWER': 'Very Good CLI is not installed.'},
      );

      expect(jsonDecode(out), {
        'additionalContext': 'Very Good CLI is not installed.',
      });
    });

    test('prints nothing when the script prints nothing', () async {
      final (_, out, _) = await run(edit('${temp.path}/a.dart'));

      expect(out, isEmpty);
    });

    test('keeps a deny, and lets any other failure through', () async {
      final payload = {
        'tool_name': 'Bash',
        'tool_input': {'command': 'ls'},
      };

      final (denied, _, _) = await run(payload, env: {'EXIT': '2'});
      final (errored, _, _) = await run(payload, env: {'EXIT': '1'});

      expect(denied, 2);
      expect(errored, 0);
    });

    test('turns a denial on stderr into the decision Copilot reads', () async {
      final (code, out, err) = await run(
        {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'dart test'},
        },
        env: {'EXIT': '2', 'COMPLAINT': 'use the MCP tool'},
      );

      expect(code, 2);
      expect(jsonDecode(out), {
        'permissionDecision': 'deny',
        'permissionDecisionReason': 'use the MCP tool',
      });
      expect(err, 'use the MCP tool\n');
    });

    test('turns a complaint on stderr after a tool into context', () async {
      final (code, out, err) = await run(
        edit('${temp.path}/a.dart'),
        env: {'EXIT': '2', 'COMPLAINT': '1 issue found.'},
      );

      expect(code, 0);
      expect(jsonDecode(out), {'additionalContext': '1 issue found.'});
      expect(err, '1 issue found.\n');
    });

    test(
      'leaves an exit 2 with an answer, or nothing said, as it is',
      () async {
        final payload = {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'ls'},
        };

        final (quiet, silence, _) = await run(payload, env: {'EXIT': '2'});
        final (_, answered, _) = await run(
          payload,
          env: {'EXIT': '2', 'ANSWER': '{"a":1}', 'COMPLAINT': 'ignored'},
        );

        expect(quiet, 2);
        expect(silence, isEmpty);
        expect(answered, '{"a":1}\n');
      },
    );

    test('answers the exit, and nothing else, when jq is missing', () async {
      final bin = temp.childDirectory('bin')..createSync();
      for (final tool in ['bash', 'cat', 'mktemp', 'rm']) {
        final found = Process.runSync('bash', ['-c', 'command -v $tool']);
        bin.childLink(tool).createSync((found.stdout as String).trim());
      }
      final payload = edit('${temp.path}/a.dart');

      final (code, out, _) = await run(
        payload,
        path: bin.path,
        env: {'EXIT': '1', 'ANSWER': 'plain'},
      );

      expect(code, 0);
      expect(out, 'plain\n');
      expect(runs().single.$2, payload);
    });

    test('re-runs itself when the script is executed directly', () async {
      await run(edit('${temp.path}/a.dart'), direct: true);

      expect(
        (runs().single.$2['tool_input']! as Map)['file_path'],
        '${temp.path}/a.dart',
      );
    });
  }, skip: bash ? null : 'needs bash and jq on PATH');
}
