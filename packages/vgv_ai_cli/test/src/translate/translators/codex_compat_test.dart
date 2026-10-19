import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Runs [codexPreamble] and [codexCompatScript] for real, through bash and
/// jq, on top of a stub script that records every payload it is handed.
/// Skipped where bash or jq is missing.
void main() {
  final bash = Process.runSync('bash', ['-c', 'command -v jq']).exitCode == 0;

  group('the Codex compat script', () {
    late Directory temp;
    late Directory pluginRoot;
    late File compat;
    late File script;
    late File log;

    /// Writes the script under test: the preamble, scoped to [agent] when
    /// given, over a stub body.
    void writeScript({String agent = ''}) {
      final preamble = codexPreamble
          .replaceAll('__ROOT__', '"${pluginRoot.path}"')
          .replaceAll('__AGENT__', '"$agent"')
          .replaceAll('__COMPAT__', '"${compat.path}"');
      script.writeAsStringSync(
        '#!/bin/bash\n$preamble'
        // What a plugin script does: read the payload once, act on it. This
        // one records the root it sees and the payload, answers per file when
        // asked to, and fails for the files it is told to.
        r'''
input=$(cat)
printf '%s\x1f%s\x1e' "$CLAUDE_PLUGIN_ROOT" "$input" >> "$LOG"
# A pair names a file; it matches the run whose file_path ends with it, not
# the patch text, which names every file.
for pair in ${ANSWERS:-}; do
  case "$input" in *"${pair%%=*}\""*)
    printf '{"hookSpecificOutput":{"permissionDecision":"%s"}}\n' "${pair#*=}"
  ;; esac
done
for pair in ${FAILURES:-}; do
  case "$input" in *"${pair%%=*}\""*) exit "${pair#*=}" ;; esac
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
      compat = temp.childFile(CodexTranslator.compatScript)
        ..writeAsStringSync(codexCompatScript);
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
    Map<String, Object?> patch(
      List<String> lines, {
      String event = 'PostToolUse',
      String? cwd,
    }) => {
      'hook_event_name': event,
      'cwd': cwd ?? temp.path,
      'tool_name': 'apply_patch',
      'tool_input': {
        'command': ['*** Begin Patch', ...lines, '*** End Patch'].join('\n'),
      },
    };

    /// The tool and file of each run, as `Edit /path`.
    List<String> edits() => [
      for (final (_, payload) in runs())
        switch (payload) {
          {'tool_name': final tool, 'tool_input': {'file_path': final path}} =>
            '$tool $path',
          _ => throw StateError('no file in $payload'),
        },
    ];

    test('runs the script once per file on disk after the tool', () async {
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
      expect(edits(), [
        'Edit ${temp.path}/old.dart',
        'Edit ${temp.path}/renamed.dart',
        'Write ${temp.path}/lib/added.dart',
      ]);
    });

    test('hands a guard the files a patch is about to add', () async {
      // Before the tool runs nothing is on disk yet, so the disk says
      // nothing about which files matter.
      await run(patch(['*** Add File: new.dart'], event: 'PreToolUse'));

      expect(edits(), ['Write ${temp.path}/new.dart']);
    });

    test(
      'resolves a relative path against a cwd with a trailing slash',
      () async {
        temp.childFile('a.dart').writeAsStringSync('');

        await run(patch(['*** Update File: a.dart'], cwd: '${temp.path}/'));

        expect(edits(), ['Edit ${temp.path}/a.dart']);
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

    test('lets a deny win over an earlier allow', () async {
      temp.childFile('a.dart').writeAsStringSync('');
      temp.childFile('b.dart').writeAsStringSync('');

      final (code, out) = await run(
        patch(['*** Update File: a.dart', '*** Update File: b.dart']),
        env: {'ANSWERS': 'a.dart=allow b.dart=deny'},
      );

      expect(code, 0);
      expect(jsonDecode(out), {
        'hookSpecificOutput': {'permissionDecision': 'deny'},
      });
    });

    test('prints one answer when every file allows', () async {
      temp.childFile('a.dart').writeAsStringSync('');
      temp.childFile('b.dart').writeAsStringSync('');

      final (_, out) = await run(
        patch(['*** Update File: a.dart', '*** Update File: b.dart']),
        env: {'ANSWERS': 'a.dart=allow b.dart=allow'},
      );

      expect(out, '{"hookSpecificOutput":{"permissionDecision":"allow"}}\n');
    });

    test('passes a patch naming no file on disk through as it came', () async {
      final payload = patch(['*** Delete File: gone.dart']);

      final (code, _) = await run(payload);

      expect(code, 0);
      expect(runs().single.$2, payload);
    });

    test(
      'leaves a shell command alone, even one that looks like a patch',
      () async {
        temp.childFile('a.dart').writeAsStringSync('');
        final payload = {
          'hook_event_name': 'PreToolUse',
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
