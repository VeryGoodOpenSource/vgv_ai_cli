import 'dart:convert';

import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  group('CopilotTranslator', () {
    const translator = CopilotTranslator();

    test('configures Copilot', () {
      expect(translator.harness, Harness.copilot);
    });

    test('declares MCP servers with the type Copilot expects', () {
      final json = translator.settings(
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
              args: ['mcp-server'],
              env: {'TOKEN': 'x'},
            ),
          ],
        ),
      );

      expect(jsonDecode(json), {
        'mcpServers': {
          'docs': {
            'type': 'http',
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
          'dart': {
            'type': 'local',
            'command': 'dart',
            'args': ['mcp-server'],
            'env': {'TOKEN': 'x'},
          },
        },
      });
    });

    test('frames an agent with its name and description', () {
      final fields = translator.agent(
        agentAsset('reviewer'),
        instructions: 'You review code.\n',
      );

      expect(frontmatterValues(fields.frontmatter), {
        'name': 'reviewer',
        'description': 'reviews code',
      });
      expect(fields.toml, isNull);
    });

    test('spells no command, since Copilot invokes skills by name', () {
      final fs = MemoryFileSystem.test();

      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    test('runs the hooks', () {
      expect(translator.runsHooks, isTrue);
    });

    test('keeps its copy of the scripts beside the hooks folder', () {
      // Copilot reads every *.json under ~/.copilot/hooks/, so a plugin's own
      // JSON copied there would be read as a hooks file.
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(
        translator.hooksRoot(home).path,
        '/home/dev/.copilot/vgv_ai/hooks',
      );
    });

    group('hooks', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      /// The whole file [hooks] translates to.
      Map<String, Object?> file(List<HookAsset> hooks) {
        final json = translator.hooks(
          pluginAssets(hooks: hooks),
          hooksRoot: fs.directory('/home/.copilot/vgv_ai/hooks'),
        )!;
        return jsonDecode(json) as Map<String, Object?>;
      }

      /// The entries [hooks] translates to, under [event].
      List<Map<String, Object?>> entries(List<HookAsset> hooks, String event) {
        final events = file(hooks)['hooks']! as Map<String, Object?>;
        return (events[event]! as List<Object?>).cast();
      }

      test("are a version 1 file under Claude Code's event names", () {
        final hooks = file([hookAsset(fs), hookAsset(fs, event: 'Stop')]);

        expect(hooks['version'], 1);
        expect((hooks['hooks']! as Map).keys, ['PostToolUse', 'Stop']);
      });

      test('spell each command as one entry under bash, timed in seconds', () {
        // Copilot reads a hook registered under the PascalCase event name
        // with Claude's matcher semantics, so the matcher carries over.
        final entry = entries([
          hookAsset(fs, matcher: 'Edit|Write'),
        ], 'PostToolUse').single;

        expect(entry, {
          'type': 'command',
          'matcher': 'Edit|Write',
          'bash': [
            'bash "/home/.copilot/vgv_ai/hooks/vgv-wingspan"',
            'hooks/scripts/analyze.sh',
          ].join('/'),
          'timeoutSec': 30,
        });
      });

      test('give every command of one matcher its own entry', () {
        final hook = hookAsset(
          fs,
          matcher: 'Edit',
          commands: const [
            HookCommand(type: 'command', command: 'a.sh', timeout: 5),
            HookCommand(type: 'command', command: 'b.sh'),
          ],
        );

        final found = entries([hook], 'PostToolUse');

        expect(found.map((e) => e['bash']), ['a.sh', 'b.sh']);
        expect(found.map((e) => e['matcher']), ['Edit', 'Edit']);
        expect(found.last, isNot(contains('timeoutSec')));
      });

      test('spell an MCP tool the way Copilot names it', () {
        // Claude Code names an MCP tool mcp__<server>__<tool>, Copilot
        // <server>-<tool>, and the matcher is a pattern over those names.
        final entry = entries([
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'Bash|mcp__.*very-good-cli__.*',
          ),
        ], 'PreToolUse').single;

        expect(entry['matcher'], 'Bash|.*very-good-cli-.*');
      });

      test('leave a hook that matches no tool with no matcher', () {
        final entry = entries([
          hookAsset(fs, event: 'SessionStart'),
        ], 'SessionStart').single;

        expect(entry, isNot(contains('matcher')));
      });

      test('leave out a handler that runs no shell command', () {
        final hook = hookAsset(
          fs,
          commands: const [
            HookCommand(type: 'prompt', command: 'say-hello'),
            HookCommand(type: 'command', command: 'a.sh'),
          ],
        );

        expect(entries([hook], 'PostToolUse').single['bash'], 'a.sh');
      });

      test('leave out a hook an agent declares for itself', () {
        // Copilot's tool payload names no agent, so flutter-reviewer's Bash
        // guard would run for every agent, which is not what it declares.
        final hooks = [
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'Bash',
            agent: 'flutter-reviewer',
          ),
        ];

        expect(
          translator.hooks(
            pluginAssets(hooks: hooks),
            hooksRoot: fs.directory('/home/.copilot/vgv_ai/hooks'),
          ),
          isNull,
        );
      });

      test('are null when the plugins ship none', () {
        expect(
          translator.hooks(
            pluginAssets(),
            hooksRoot: fs.directory('/home/.copilot/vgv_ai/hooks'),
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
        hooksRoot: fs.directory('/home/.copilot/vgv_ai/hooks'),
      );

      test("copy the plugin's hooks folder under its name, registry aside", () {
        final changes = files([hookAsset(fs)]);

        expect(changes.map((c) => c.file.path), [
          '/home/.copilot/vgv_ai/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/.copilot/vgv_ai/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.copilot});
      });

      test(
        "put Copilot's preamble below the shebang of a script a hook runs",
        () {
          final script = files([hookAsset(fs)])
              .singleWhere((c) => path.basename(c.file.path) == 'analyze.sh')
              .contents;
          final preamble = CopilotTranslator.preamble.replaceAll(
            '__ROOT__',
            '"/plugins/vgv-wingspan"',
          );

          expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
        },
      );

      test('copy nothing for a hook an agent declares for itself', () {
        expect(
          files([hookAsset(fs, matcher: 'Bash', agent: 'flutter-reviewer')]),
          isEmpty,
        );
      });
    });

    group('notes', () {
      late MemoryFileSystem fs;

      setUp(() => fs = MemoryFileSystem.test());

      test('say nothing about hooks Copilot runs as declared', () {
        expect(translator.notes(pluginAssets(hooks: [hookAsset(fs)])), isEmpty);
      });

      test('say that a hook an agent declares for itself is left out', () {
        final notes = translator.notes(
          pluginAssets(
            hooks: [
              hookAsset(
                fs,
                event: 'PreToolUse',
                matcher: 'Bash',
                agent: 'flutter-reviewer',
              ),
            ],
          ),
        );

        expect(notes.single.subject, "flutter-reviewer's PreToolUse hook");
        expect(notes.single.reason, contains('names no agent'));
      });

      test('say that a handler running no shell command is left out', () {
        final notes = translator.notes(
          pluginAssets(
            hooks: [
              hookAsset(
                fs,
                commands: const [HookCommand(type: 'prompt', command: 'hi')],
              ),
            ],
          ),
        );

        expect(notes.single.subject, '1 prompt handler(s)');
        expect(notes.single.reason, contains('shell command only'));
      });

      test('count the handlers left out per type', () {
        final notes = translator.notes(
          pluginAssets(
            hooks: [
              hookAsset(
                fs,
                commands: const [
                  HookCommand(type: 'prompt', command: 'a'),
                  HookCommand(type: 'http', command: 'b'),
                  HookCommand(type: 'prompt', command: 'c'),
                ],
              ),
            ],
          ),
        );

        expect(notes.map((n) => n.subject), [
          '2 prompt handler(s)',
          '1 http handler(s)',
        ]);
      });

      test('carry what could not be copied as intended', () {
        final hook = hookAsset(fs);
        hook.pluginRoot.childDirectory('hooks').deleteSync(recursive: true);

        expect(
          translator.notes(pluginAssets(hooks: [hook])).single.reason,
          contains('has gone away'),
        );
      });
    });
  });
}
