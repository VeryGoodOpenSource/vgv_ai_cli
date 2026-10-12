import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [CodexTranslator.preamble] for real, through bash and jq, on top of a
/// stub script that records every payload it is handed.
///
/// The Dart suite otherwise asserts only where the preamble is placed, and a
/// shell program that decides when an edit gets analyzed and when a guard may
/// deny deserves to be executed. Skipped where bash or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Codex preamble', () {
    late Directory temp;
    late Directory pluginRoot;
    late File script;
    late File log;

    /// Writes the script under test: the preamble, scoped to [agent] when
    /// given, over a stub body.
    void writeScript({String agent = ''}) {
      final preamble = CodexTranslator.preamble
          .replaceAll('__ROOT__', '"${pluginRoot.path}"')
          .replaceAll('__AGENT__', '"$agent"');
      script.writeAsStringSync(
        '#!/bin/bash\n$preamble'
        // What a plugin script would do: read the payload once, act on it.
        // This one records the root it sees and the payload, answers when
        // asked to, and fails for the files it is told to.
        r'''
input=$(cat)
printf '%s\x1f%s\x1e' "$CLAUDE_PLUGIN_ROOT" "$input" >> "$LOG"
[ -z "${ANSWER:-}" ] || printf '%s\n' "$ANSWER"
for pair in ${FAILURES:-}; do
  case "$input" in *"${pair%%=*}"*) exit "${pair#*=}" ;; esac
done
exit 0
''',
      );
      Process.runSync('chmod', ['755', script.path]);
    }

    setUp(() {
      temp = const LocalFileSystem().systemTempDirectory.createTempSync();
      addTearDown(() => temp.deleteSync(recursive: true));
      // A space and a quote, since the root is spliced into the script.
      pluginRoot = temp.childDirectory("it's a plugin")..createSync();
      log = temp.childFile('log');
      script = temp.childFile('hook.sh');
      writeScript();
    });

    /// Runs the script on [payload], returning its exit code and stdout.
    Future<(int, String)> run(
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
      final out = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain<void>();
      return (await process.exitCode, out);
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

    /// What Codex sends for an apply_patch whose headers are [lines].
    Map<String, Object?> patch(List<String> lines, {String? cwd}) => {
      'cwd': cwd ?? temp.path,
      'tool_name': 'apply_patch',
      'tool_input': {
        'command': ['*** Begin Patch', ...lines, '*** End Patch'].join('\n'),
      },
    };

    test(
      'runs the script once per file on disk, as an Edit or a Write',
      () async {
        temp.childFile('old.dart').writeAsStringSync('');
        temp.childFile('renamed.dart').writeAsStringSync('');
        temp.childDirectory('lib').createSync();
        temp.childFile('lib/added.dart').writeAsStringSync('');

        final (code, _) = await run(
          patch([
            '*** Update File: old.dart',
            '*** Delete File: gone.dart',
            '*** Update File: was.dart',
            '*** Move to: renamed.dart',
            '*** Add File: lib/added.dart',
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
      },
    );

    test(
      'resolves a relative path against a cwd with a trailing slash',
      () async {
        temp.childFile('a.dart').writeAsStringSync('');

        await run(patch(['*** Update File: a.dart'], cwd: '${temp.path}/'));

        expect(
          (runs().single.$2['tool_input']! as Map)['file_path'],
          '${temp.path}/a.dart',
        );
      },
    );

    test('hands the script the plugin root, quoted as it was', () async {
      temp.childFile('a.dart').writeAsStringSync('');

      await run(patch(['*** Update File: a.dart']));

      expect(runs().single.$1, pluginRoot.path);
    });

    test('exits with the first failure after running every file', () async {
      for (final name in ['a.dart', 'b.dart', 'c.dart']) {
        temp.childFile(name).writeAsStringSync('');
      }

      final (code, _) = await run(
        patch([
          '*** Update File: a.dart',
          '*** Update File: b.dart',
          '*** Update File: c.dart',
        ]),
        env: {'FAILURES': 'b.dart=2 c.dart=3'},
      );

      expect(code, 2);
      expect(runs(), hasLength(3));
    });

    test('prints the first answer only, so the harness sees one', () async {
      temp.childFile('a.dart').writeAsStringSync('');
      temp.childFile('b.dart').writeAsStringSync('');

      final (_, out) = await run(
        patch(['*** Update File: a.dart', '*** Update File: b.dart']),
        env: {'ANSWER': '{"decision":"deny"}'},
      );

      expect(out, '{"decision":"deny"}\n');
    });

    test('passes a patch naming no file on disk through as it came', () async {
      final payload = patch(['*** Add File: not_yet.dart']);

      final (code, _) = await run(payload);

      expect(code, 0);
      expect(runs().single.$2, payload);
    });

    test(
      'leaves a shell command alone, even one that looks like a patch',
      () async {
        // A Bash heredoc holding a patch header must not turn a Bash payload
        // into a Write, or a guard on Bash would stand aside.
        temp.childFile('a.dart').writeAsStringSync('');
        final payload = {
          'cwd': temp.path,
          'tool_name': 'Bash',
          'tool_input': {
            'command': "cat <<'EOF'\n*** Add File: a.dart\nEOF\ndart test",
          },
        };

        await run(payload);

        expect(runs().single.$2, payload);
      },
    );

    test("passes Claude Code's own payload through as it came", () async {
      final payload = {
        'tool_name': 'Edit',
        'tool_input': {'file_path': '${temp.path}/a.dart'},
      };

      await run(payload);

      expect(runs().single.$2, payload);
    });

    test('passes every payload through when jq is missing', () async {
      temp.childFile('a.dart').writeAsStringSync('');
      final bin = temp.childDirectory('bin')..createSync();
      for (final tool in ['bash', 'cat']) {
        final found = Process.runSync('bash', ['-c', 'command -v $tool']);
        bin.childLink(tool).createSync((found.stdout as String).trim());
      }
      final payload = patch(['*** Update File: a.dart']);

      final (code, _) = await run(payload, path: bin.path);

      expect(code, 0);
      expect(runs().single.$2, payload);
    });

    test('runs a scoped script for its agent alone', () async {
      writeScript(agent: 'flutter-reviewer');
      final mine = {
        'tool_name': 'Bash',
        'agent_type': 'flutter-reviewer',
        'tool_input': {'command': 'git status'},
      };
      final theirs = {...mine, 'agent_type': 'planner'};
      final nobody = {...mine}..remove('agent_type');

      final (code, _) = await run(theirs);
      await run(nobody);
      await run(mine);

      expect(code, 0);
      expect(runs().map((r) => r.$2), [mine]);
    });

    test('re-runs itself when the script is executed directly', () async {
      temp.childFile('a.dart').writeAsStringSync('');

      await run(patch(['*** Update File: a.dart']), direct: true);

      expect(runs().single.$2['tool_name'], 'Edit');
    });
  }, skip: bash ? null : 'needs bash and jq on PATH');
}
