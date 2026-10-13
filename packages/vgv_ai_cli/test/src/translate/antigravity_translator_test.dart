import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev');
  });

  group('AntigravityTranslator', () {
    const translator = AntigravityTranslator();
    const hooksRoot = '/home/dev/.gemini/antigravity-cli/plugins/vgv/hooks';

    test('configures Antigravity', () {
      expect(translator.harness, Harness.antigravity);
    });

    test('keeps its own copy of the skills inside the plugin', () {
      expect(translator.readsSharedSkills, isFalse);
      expect(
        translator.skillsRoot(home).path,
        '/home/dev/.gemini/antigravity-cli/plugins/vgv/skills',
      );
    });

    test('declares that it runs the hooks, which the notes read', () {
      expect(translator.runsHooks, isTrue);
      expect(translator.hooksRoot(home).path, hooksRoot);
    });

    test('declares MCP servers with serverUrl for a remote one', () {
      final json = translator.settings(
        pluginAssets(
          mcpServers: [
            const RemoteMCPServer(
              name: 'docs',
              url: 'https://docs.example',
              headers: {'X-Region': 'us'},
            ),
            const RemoteMCPServer(name: 'open', url: 'https://open.example'),
            const LocalMCPServer(
              name: 'dart',
              command: 'dart',
              args: ['mcp-server'],
            ),
          ],
        ),
      );

      expect(jsonDecode(json), {
        'mcpServers': {
          'docs': {
            'serverUrl': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
          'open': {'serverUrl': 'https://open.example'},
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        },
      });
    });

    group('agent', () {
      test('names its skills in the frontmatter, relative to the plugin', () {
        final fields = translator.agent(
          agentAsset('reviewer', skills: ['bloc', 'testing']),
          instructions: 'shared',
        );

        expect(frontmatterValues(fields.frontmatter), {
          'name': 'reviewer',
          'description': 'reviews code',
          'subagent': true,
          'skills': ['skills/bloc', 'skills/testing'],
        });
      });

      test('leaves the skills key out when it declares none', () {
        final fields = translator.agent(
          agentAsset('reviewer'),
          instructions: 'shared',
        );

        expect(
          frontmatterValues(fields.frontmatter),
          isNot(contains('skills')),
        );
      });

      test('keeps the body as its instructions, not the shared pointer', () {
        final fields = translator.agent(
          agentAsset('reviewer', body: 'You review code.'),
          instructions: 'shared, with a skills pointer\n',
        );

        expect(fields.instructions, 'You review code.\n');
      });
    });

    test('spells no command, since every skill becomes one', () {
      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    group('hooks', () {
      /// The whole file [hooks] translates to.
      Map<String, Object?> file(List<HookAsset> hooks) {
        final json = translator.hooks(
          pluginAssets(hooks: hooks),
          hooksRoot: fs.directory(hooksRoot),
        )!;
        return jsonDecode(json) as Map<String, Object?>;
      }

      /// The registrations [hooks] translate to, under [event] of the test
      /// plugin.
      List<Map<String, Object?>> entries(List<HookAsset> hooks, String event) {
        final events = file(hooks)['vgv-wingspan']! as Map<String, Object?>;
        return (events[event]! as List<Object?>).cast();
      }

      test('are one set per source plugin, under the shared event names', () {
        final hooks = file([hookAsset(fs), hookAsset(fs, event: 'Stop')]);

        expect(hooks.keys, ['vgv-wingspan']);
        expect((hooks['vgv-wingspan']! as Map).keys, ['PostToolUse', 'Stop']);
      });

      test('name the event in the command, timed in seconds', () {
        final entry = entries([hookAsset(fs)], 'PostToolUse').single;

        expect(entry, {
          'hooks': [
            {
              'type': 'command',
              'command': [
                'VGV_HOOK_EVENT=PostToolUse bash "$hooksRoot/vgv-wingspan"',
                'hooks/scripts/analyze.sh',
              ].join('/'),
              'timeout': 30,
            },
          ],
        });
      });

      test('name the tools a matcher names the way Antigravity does', () {
        final entry = entries([
          hookAsset(fs, matcher: 'Edit|Write'),
        ], 'PostToolUse').single;

        expect(
          entry['matcher'],
          'replace_file_content|multi_replace_file_content|write_to_file',
        );
      });

      test('match an MCP tool on its server name', () {
        final entry = entries([
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'Bash|mcp__.*very-good-cli__.*',
          ),
        ], 'PreToolUse').single;

        expect(entry['matcher'], 'run_command|.*very-good-cli.*');
      });

      test('leave a hook that matches no tool with no matcher', () {
        final entry = entries([
          hookAsset(fs, event: 'SessionStart'),
        ], 'SessionStart').single;

        expect(entry, isNot(contains('matcher')));
      });

      test('leave out a handler that runs no shell command', () {
        final entry = entries([
          hookAsset(
            fs,
            commands: const [
              HookCommand(type: 'prompt', command: 'say-hello'),
              HookCommand(type: 'command', command: 'a.sh'),
            ],
          ),
        ], 'PostToolUse').single;

        expect((entry['hooks']! as List).single, {
          'type': 'command',
          'command': 'VGV_HOOK_EVENT=PostToolUse a.sh',
        });
      });

      test('are null when nothing can run', () {
        final root = fs.directory(hooksRoot);

        expect(translator.hooks(pluginAssets(), hooksRoot: root), isNull);
        expect(
          translator.hooks(
            pluginAssets(hooks: [hookAsset(fs, agent: 'flutter-reviewer')]),
            hooksRoot: root,
          ),
          isNull,
        );
        expect(
          translator.hooks(
            pluginAssets(hooks: [hookAsset(fs, event: 'UserPromptSubmit')]),
            hooksRoot: root,
          ),
          isNull,
        );
      });
    });

    group('hookFiles', () {
      List<PlannedChange> files(List<HookAsset> hooks) => translator.hookFiles(
        pluginAssets(hooks: hooks),
        hooksRoot: fs.directory(hooksRoot),
      );

      test("copy the plugin's hooks folder under its name, registry aside", () {
        final changes = files([hookAsset(fs)]);

        expect(changes.map((c) => c.file.path), [
          '$hooksRoot/vgv-wingspan/hooks/scripts/analyze.sh',
          '$hooksRoot/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.antigravity});
      });

      test("put Antigravity's preamble below the shebang of a script", () {
        final script = files([hookAsset(fs)])
            .singleWhere((c) => path.basename(c.file.path) == 'analyze.sh')
            .contents;
        final preamble = AntigravityTranslator.preamble.replaceAll(
          '__ROOT__',
          '"/plugins/vgv-wingspan"',
        );

        expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
      });

      test('copy nothing for a hook Antigravity cannot run', () {
        expect(files([hookAsset(fs, agent: 'flutter-reviewer')]), isEmpty);
        expect(files([hookAsset(fs, event: 'Notification')]), isEmpty);
      });
    });

    group('notes', () {
      test('say that nothing a hook says after a tool reaches the agent', () {
        final notes = translator.notes(pluginAssets(hooks: [hookAsset(fs)]));

        expect(notes.single.subject, 'the PostToolUse hooks');
        expect(notes.single.reason, contains('hears none of it'));
      });

      test('say nothing about a hook before a tool', () {
        expect(
          translator.notes(
            pluginAssets(hooks: [hookAsset(fs, event: 'PreToolUse')]),
          ),
          isEmpty,
        );
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

      test('say that a hook on an event Antigravity lacks is left out', () {
        final notes = translator.notes(
          pluginAssets(hooks: [hookAsset(fs, event: 'Notification')]),
        );

        expect(notes.single.subject, "vgv-wingspan's Notification hook");
        expect(
          notes.single.reason,
          'Antigravity has no Notification event, so it is left out',
        );
      });

      test('say that a handler running no shell command is left out', () {
        final notes = translator.notes(
          pluginAssets(
            hooks: [
              hookAsset(
                fs,
                event: 'PreToolUse',
                commands: const [HookCommand(type: 'prompt', command: 'hi')],
              ),
            ],
          ),
        );

        expect(notes.single.subject, '1 prompt handler(s)');
        expect(notes.single.reason, contains('shell command only'));
      });

      test('carry what could not be copied as intended', () {
        final hook = hookAsset(fs, event: 'PreToolUse');
        hook.pluginRoot.childDirectory('hooks').deleteSync(recursive: true);

        expect(
          translator.notes(pluginAssets(hooks: [hook])).single.reason,
          contains('has gone away'),
        );
      });

      test('are empty when everything translates', () {
        expect(
          translator.notes(pluginAssets(agents: [agentAsset('reviewer')])),
          isEmpty,
        );
      });
    });
  });
}
