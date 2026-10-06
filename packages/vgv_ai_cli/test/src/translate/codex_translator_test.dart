import 'dart:convert';

import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  group('CodexTranslator', () {
    const translator = CodexTranslator();

    test('configures Codex', () {
      expect(translator.harness, Harness.codex);
    });

    test('declares that it runs the hooks, which the notes read', () {
      expect(translator.runsHooks, isTrue);
    });

    test('declares MCP servers as TOML tables, headers as http_headers', () {
      final toml = translator.settings(
        pluginAssets(
          mcpServers: [
            const RemoteMCPServer(
              name: 'docs',
              url: 'https://docs.example',
              headers: {'X-Region': 'us'},
            ),
            const LocalMCPServer(
              name: 'dart',
              command: 'dart',
              env: {'TOKEN': 'x'},
            ),
          ],
        ),
      );

      expect(TomlDocument.parse(toml).toMap(), {
        'mcp_servers': {
          'docs': {
            'url': 'https://docs.example',
            'http_headers': {'X-Region': 'us'},
          },
          'dart': {
            'command': 'dart',
            'env': {'TOKEN': 'x'},
          },
        },
      });
    });

    group('agents', () {
      test('carry the three keys the loader needs, as parseable TOML', () {
        final toml = translator
            .agent(agentAsset('reviewer'), instructions: 'You review code.\n')
            .toml!;

        expect(TomlDocument.parse(toml).toMap(), {
          'name': 'reviewer',
          'description': 'reviews code',
          'developer_instructions': 'You review code.\n',
        });
      });

      test(
        'survive instructions full of quotes, backticks and backslashes',
        () {
          const instructions = 'Say "no" to `rm -rf`\\ and \'"""\' too.\n';

          final toml = translator
              .agent(agentAsset('reviewer'), instructions: instructions)
              .toml!;

          expect(
            TomlDocument.parse(toml).toMap()['developer_instructions'],
            instructions,
          );
        },
      );
    });

    test('spells no command, since Codex reads no custom prompts', () {
      final fs = MemoryFileSystem.test();

      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    group('hooks', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      /// The registrations [hooks] translates to, under their event.
      Map<String, Object?> events(List<HookAsset> hooks) {
        final json = translator.hooks(
          pluginAssets(hooks: hooks),
          hooksRoot: fs.directory('/home/.codex/hooks'),
        )!;
        return (jsonDecode(json) as Map<String, Object?>)['hooks']!
            as Map<String, Object?>;
      }

      test("spell a file-edit matcher with Codex's own tool name", () {
        // Codex writes every edit through apply_patch, and Claude's two names
        // are kept because Codex documents all three as interchangeable.
        final registrations =
            events([hookAsset(fs, matcher: 'Edit|Write')])['PostToolUse']!
                as List<Object?>;

        expect(
          (registrations.single! as Map)['matcher'],
          'Edit|apply_patch|Write',
        );
      });

      test('carry over a matcher Codex spells the same way', () {
        for (final matcher in ['Bash', 'mcp__.*very-good-cli__.*']) {
          final registrations =
              events([
                    hookAsset(fs, event: 'PreToolUse', matcher: matcher),
                  ])['PreToolUse']!
                  as List<Object?>;

          expect((registrations.single! as Map)['matcher'], matcher);
        }
      });

      test('leave a hook that matches no tool with no matcher', () {
        final registrations =
            events([hookAsset(fs, event: 'SessionStart')])['SessionStart']!
                as List<Object?>;

        expect(registrations.single! as Map, isNot(contains('matcher')));
      });

      test("point a command at Codex's copy of the plugin", () {
        // The copy is where the preamble lives, so the command has to run
        // that script and not the plugin's own.
        final registrations =
            events([hookAsset(fs)])['PostToolUse']! as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(
          (commands.single! as Map)['command'],
          'bash /home/.codex/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
        );
      });

      test('carry a handler that runs no shell command as it is', () {
        // Codex takes an mcp_tool handler and Claude a prompt one. Neither
        // names a script, so there is nothing to point elsewhere.
        final registrations =
            events([
                  hookAsset(
                    fs,
                    matcher: 'Edit',
                    commands: const [
                      HookCommand(type: 'prompt', command: 'say-hello'),
                    ],
                  ),
                ])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect((commands.single! as Map)['command'], 'say-hello');
      });

      test('carry the type and the timeout, and leave an absent one out', () {
        final registrations =
            events([
                  hookAsset(
                    fs,
                    commands: const [
                      HookCommand(type: 'command', command: 'a.sh', timeout: 5),
                      HookCommand(type: 'prompt', command: 'b.sh'),
                    ],
                  ),
                ])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(commands.first! as Map, containsPair('type', 'command'));
        expect(commands.first! as Map, containsPair('timeout', 5));
        expect(commands.last! as Map, containsPair('type', 'prompt'));
        expect(commands.last! as Map, containsPair('command', 'b.sh'));
        expect(commands.last! as Map, isNot(contains('timeout')));
      });

      test('group every registration of one event together', () {
        final registrations =
            events([
                  hookAsset(fs, matcher: 'Edit'),
                  hookAsset(fs, matcher: 'Write'),
                ])['PostToolUse']!
                as List<Object?>;

        expect(registrations, hasLength(2));
      });

      test('are null when the plugins ship none', () {
        expect(
          translator.hooks(
            pluginAssets(),
            hooksRoot: fs.directory('/home/.codex/hooks'),
          ),
          isNull,
        );
      });

      test('are null when no hook names a tool Codex has', () {
        // Codex reads files through the shell, so wingspan's Read|Glob|Grep
        // hook could never fire and nothing is left to write.
        expect(
          translator.hooks(
            pluginAssets(hooks: [hookAsset(fs, matcher: 'Read|Glob|Grep')]),
            hooksRoot: fs.directory('/home/.codex/hooks'),
          ),
          isNull,
        );
      });
    });

    group('hookFiles', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      List<PlannedChange> files(List<HookAsset> hooks) => translator.hookFiles(
        pluginAssets(hooks: hooks),
        hooksRoot: fs.directory('/home/.codex/hooks'),
      );

      PlannedChange at(List<PlannedChange> changes, String suffix) =>
          changes.singleWhere((c) => c.file.path.endsWith(suffix));

      test("copy the plugin's hooks folder under its name, registry aside", () {
        // Every neighbour comes along, because a script sources and reads
        // files by its own location. The plugin's hooks.json is what hooks()
        // translated, so a copy of it would only mislead.
        final changes = files([hookAsset(fs)]);

        expect(changes.map((c) => c.file.path), [
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/.codex/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.codex});
      });

      test('copy each file from its source, so it keeps its mode', () {
        final change = at(files([hookAsset(fs)]), 'common.sh');

        expect(
          change.source?.path,
          '/plugins/vgv-wingspan/hooks/scripts/common.sh',
        );
        expect(change.contents, 'hi() { echo hi; }\n');
      });

      test('put the preamble below the shebang of a script a hook runs', () {
        final script = at(files([hookAsset(fs)]), 'analyze.sh').contents;
        final preamble = CodexTranslator.preamble.replaceAll(
          '__ROOT__',
          "'/plugins/vgv-wingspan'",
        );

        expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
      });

      test('put the preamble at the top of a script with no shebang', () {
        final hook = hookAsset(
          fs,
          commands: const [
            HookCommand(
              type: 'command',
              command: r'${PLUGIN_ROOT}/hooks/run.sh',
            ),
          ],
        );
        hook.pluginRoot
            .childDirectory('hooks')
            .childFile('run.sh')
            .writeAsStringSync('echo run\n');

        final script = at(files([hook]), 'run.sh').contents;

        expect(script, startsWith('# Added by vgv_ai install'));
        expect(script, endsWith('fi\necho run\n'));
      });

      test('quote a plugin root that holds a quote', () {
        final root = fs.directory("/plugins/it's")..createSync(recursive: true);
        root.childDirectory('hooks').childFile('run.sh')
          ..createSync(recursive: true)
          ..writeAsStringSync('echo run\n');
        final hook = HookAsset(
          event: 'Stop',
          commands: const [
            HookCommand(
              type: 'command',
              command: r'${PLUGIN_ROOT}/hooks/run.sh',
            ),
          ],
          plugin: 'quoted',
          pluginRoot: root,
        );

        expect(
          at(files([hook]), 'run.sh').contents,
          contains(r"export CLAUDE_PLUGIN_ROOT='/plugins/it'\''s'"),
        );
      });

      test('leave a script no shell command names as it is', () {
        // A prompt handler names no script, and common.sh is only sourced.
        final hook = hookAsset(
          fs,
          commands: const [HookCommand(type: 'prompt', command: 'say-hello')],
        );

        for (final change in files([hook])) {
          expect(change.contents, isNot(contains('vgv_ai install')));
        }
      });

      test('copy nothing for a hook Codex will not run', () {
        expect(files([hookAsset(fs, matcher: 'Read|Glob|Grep')]), isEmpty);
      });

      test('copy nothing for a plugin whose hooks folder has gone away', () {
        // A cache cleared between resolution and translation. hooks() still
        // names the scripts, and Codex reports the missing file when one
        // fires, which beats throwing out of install.
        final hook = hookAsset(fs);
        hook.pluginRoot.childDirectory('hooks').deleteSync(recursive: true);

        expect(files([hook]), isEmpty);
      });
    });

    group('notes', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      test('name each hook that matches no tool Codex has', () {
        final notes = translator.notes(
          pluginAssets(
            hooks: [hookAsset(fs, event: 'PreToolUse', matcher: 'Read|Glob')],
          ),
        );

        expect(notes.single.subject, 'PreToolUse Read|Glob');
        expect(notes.single.reason, contains('could never fire'));
      });

      test('ask for the trust that lets the rest run', () {
        final notes = translator.notes(pluginAssets(hooks: [hookAsset(fs)]));

        expect(notes.single.reason, contains('/hooks'));
      });

      test('say nothing about hooks when there are none', () {
        expect(translator.notes(pluginAssets()), isEmpty);
      });
    });
  });
}
