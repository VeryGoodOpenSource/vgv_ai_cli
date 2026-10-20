import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '../_assets.dart';

void main() {
  group(AntigravityTranslator, () {
    late FileSystem fs;
    late Directory home;

    setUp(() {
      fs = MemoryFileSystem.test();
      home = fs.directory('/home/dev');
    });

    const translator = AntigravityTranslator();
    const hooksRoot = '/home/dev/.gemini/config/plugins/vgv/hooks';

    test('configures Antigravity', () {
      expect(translator.harness, Harness.antigravity);
    });

    test('keeps its own copy of the skills inside the plugin', () {
      expect(translator.readsSharedSkills, isFalse);
      expect(
        translator.skillsRoot(home).path,
        '/home/dev/.gemini/config/plugins/vgv/skills',
      );
    });

    test('keeps its copy of the scripts inside the plugin', () {
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
      /// What [hooks] translate to.
      HookTranslation translation(List<HookAsset> hooks) => translator.hooks(
        pluginAssets(hooks: hooks),
        hooksRoot: fs.directory(hooksRoot),
      );

      /// The whole file [hooks] translate to.
      Map<String, Object?> file(List<HookAsset> hooks) =>
          jsonDecode(translation(hooks).fragment!) as Map<String, Object?>;

      /// The registrations [hooks] translate to, under [event] of the test
      /// plugin.
      List<Map<String, Object?>> entries(List<HookAsset> hooks, String event) {
        final events = file(hooks)['vgv-wingspan']! as Map<String, Object?>;
        return (events[event]! as List<Object?>).cast();
      }

      test('are one set per source plugin, under the shared event names', () {
        final hooks = file([hookAsset(fs), hookAsset(fs, event: 'Stop')]);

        expect(hooks.keys, ['vgv-wingspan']);
        expect(
          hooks['vgv-wingspan'],
          isA<Map<String, Object?>>().having((e) => e.keys, 'keys', [
            'PostToolUse',
            'Stop',
          ]),
        );
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

      test('match every MCP tool through the one tool that calls them', () {
        final entry = entries([
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'Bash|mcp__.*very-good-cli__.*|mcp__dart__.*',
          ),
        ], 'PreToolUse').single;

        expect(entry['matcher'], 'run_command|call_mcp_tool');
      });

      test('list the handlers themselves under an event with no tool', () {
        final entry = entries([
          hookAsset(fs, event: 'SessionStart'),
        ], 'SessionStart').single;

        expect(entry.keys, ['type', 'command', 'timeout']);
        expect(entry['command'], startsWith('VGV_HOOK_EVENT=SessionStart '));
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

        expect(entry['hooks'], [
          {'type': 'command', 'command': 'VGV_HOOK_EVENT=PostToolUse a.sh'},
        ]);
      });

      test('register nothing when nothing can run', () {
        expect(translation([]).fragment, isNull);
        expect(
          translation([hookAsset(fs, agent: 'flutter-reviewer')]).fragment,
          isNull,
        );
        expect(
          translation([hookAsset(fs, event: 'UserPromptSubmit')]).fragment,
          isNull,
        );
      });

      test('register nothing for a hook that runs no shell command', () {
        final hooks = [
          hookAsset(
            fs,
            commands: const [HookCommand(type: 'prompt', command: 'hi')],
          ),
        ];

        expect(translation(hooks).fragment, isNull);
        expect(
          translation(hooks).files.map((c) => path.basename(c.file.path)),
          isNot(contains(AntigravityTranslator.compatScript)),
        );
      });

      test("copy the plugin's hooks folder under its name, registry aside", () {
        final changes = translation([hookAsset(fs)]).files;

        expect(changes.map((c) => c.file.path), [
          '$hooksRoot/${AntigravityTranslator.compatScript}',
          '$hooksRoot/vgv-wingspan/hooks/scripts/analyze.sh',
          '$hooksRoot/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.antigravity});
      });

      test("put Antigravity's preamble below the shebang of a script", () {
        final script = translation([hookAsset(fs)]).files
            .singleWhere((c) => path.basename(c.file.path) == 'analyze.sh')
            .contents;
        final preamble = antigravityPreamble
            .replaceAll('__ROOT__', '"/plugins/vgv-wingspan"')
            .replaceAll(
              '__COMPAT__',
              '"$hooksRoot/${AntigravityTranslator.compatScript}"',
            );

        expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
      });

      test('copy nothing for a hook Antigravity cannot run', () {
        expect(
          translation([hookAsset(fs, agent: 'flutter-reviewer')]).files,
          isEmpty,
        );
        expect(
          translation([hookAsset(fs, event: 'Notification')]).files,
          isEmpty,
        );
      });
    });

    group('notes', () {
      List<TranslationNote> notesOf(List<HookAsset> hooks) => translator
          .hooks(pluginAssets(hooks: hooks), hooksRoot: fs.directory(hooksRoot))
          .notes;

      test('say that nothing a hook says after a tool reaches the agent', () {
        final notes = notesOf([hookAsset(fs)]);

        expect(notes.single.subject, 'the PostToolUse hooks');
        expect(notes.single.reason, contains('hears none of it'));
      });

      test('say nothing about a hook before a tool', () {
        expect(notesOf([hookAsset(fs, event: 'PreToolUse')]), isEmpty);
      });

      test('say that a hook an agent declares for itself is left out', () {
        final notes = notesOf([
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'Bash',
            agent: 'flutter-reviewer',
          ),
        ]);

        expect(notes.single.subject, "flutter-reviewer's PreToolUse hook");
        expect(notes.single.reason, contains('names no agent'));
      });

      test('say that a hook on an event Antigravity lacks is left out', () {
        final notes = notesOf([hookAsset(fs, event: 'Notification')]);

        expect(notes.single.subject, "vgv-wingspan's Notification hook");
        expect(
          notes.single.reason,
          'Antigravity has no Notification event, so it is left out',
        );
      });

      test('say that a handler running no shell command is left out', () {
        final notes = notesOf([
          hookAsset(
            fs,
            event: 'PreToolUse',
            commands: const [HookCommand(type: 'prompt', command: 'hi')],
          ),
        ]);

        expect(notes.single.subject, '1 prompt handler(s)');
        expect(notes.single.reason, contains('shell command only'));
      });

      test('carry what could not be copied as intended', () {
        final hook = hookAsset(fs, event: 'PreToolUse');
        hook.pluginRoot.childDirectory('hooks').deleteSync(recursive: true);

        expect(notesOf([hook]).single.reason, contains('has gone away'));
      });

      test('say nothing beyond the hooks', () {
        expect(
          translator.notes(pluginAssets(agents: [agentAsset('reviewer')])),
          isEmpty,
        );
      });
    });
  });
}
