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
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev');
  });

  group('DevinTranslator', () {
    const translator = DevinTranslator();
    const hooksRoot = '/home/dev/.config/devin/hooks';

    test('configures Devin', () {
      expect(translator.harness, Harness.devin);
    });

    test('reads the shared copy of the skills', () {
      expect(translator.readsSharedSkills, isTrue);
      expect(translator.skillsRoot(home), isNull);
    });

    test('keeps its copy of the scripts under its config directory', () {
      expect(translator.hooksRoot(home).path, hooksRoot);
    });

    test('declares MCP servers as mcp_config.json does', () {
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
            ),
          ],
        ),
      );

      expect(jsonDecode(json), {
        'mcpServers': {
          'docs': {
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        },
      });
    });

    test('names a subagent profile in its frontmatter', () {
      final fields = translator.agent(
        agentAsset('reviewer'),
        instructions: 'shared',
      );

      expect(frontmatterValues(fields.frontmatter), {
        'name': 'reviewer',
        'description': 'reviews code',
      });
      expect(fields.instructions, isNull);
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

      /// The registrations [hooks] translate to, under [event].
      List<Map<String, Object?>> entries(List<HookAsset> hooks, String event) {
        final file =
            jsonDecode(translation(hooks).fragment!) as Map<String, Object?>;
        final events = file['hooks']! as Map<String, Object?>;
        return (events[event]! as List<Object?>).cast();
      }

      test('go under the hooks key, keyed by event', () {
        final file = jsonDecode(
          translation([hookAsset(fs), hookAsset(fs, event: 'SessionStart')])
              .fragment!,
        ) as Map<String, Object?>;

        expect(file.keys, ['hooks']);
        expect((file['hooks']! as Map).keys, ['PostToolUse', 'SessionStart']);
      });

      test('point each command at the copy of the script', () {
        final entry = entries([hookAsset(fs)], 'PostToolUse').single;

        expect(entry, {
          'hooks': [
            {
              'type': 'command',
              'command':
                  'bash "$hooksRoot/vgv-wingspan"/hooks/scripts/analyze.sh',
              'timeout': 30,
            },
          ],
        });
      });

      test('name the tools a matcher names the way Devin does, anchored', () {
        final entry = entries([
          hookAsset(fs, matcher: 'Edit|Write'),
        ], 'PostToolUse').single;

        expect(entry['matcher'], r'^(edit|apply_patch|write)$');
      });

      test('keep a matcher that is not a flat list of tool names', () {
        final entry = entries([
          hookAsset(
            fs,
            event: 'PreToolUse',
            matcher: 'mcp__.*very-good-cli__.*',
          ),
        ], 'PreToolUse').single;

        expect(entry['matcher'], 'mcp__.*very-good-cli__.*');
      });

      test('leave the matcher out when the hook declares none', () {
        final entry = entries([
          hookAsset(fs, event: 'SessionStart'),
        ], 'SessionStart').single;

        expect(entry.keys, ['hooks']);
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
          'command': 'a.sh',
        });
      });

      test('register nothing when nothing can run', () {
        expect(translation([]).fragment, isNull);
        expect(
          translation([hookAsset(fs, agent: 'flutter-reviewer')]).fragment,
          isNull,
        );
        expect(
          translation([hookAsset(fs, event: 'Notification')]).fragment,
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
          isNot(contains(DevinTranslator.compatScript)),
        );
      });

      test("copy the plugin's hooks folder under its name, registry aside", () {
        final changes = translation([hookAsset(fs)]).files;

        expect(changes.map((c) => c.file.path), [
          '$hooksRoot/${DevinTranslator.compatScript}',
          '$hooksRoot/vgv-wingspan/hooks/scripts/analyze.sh',
          '$hooksRoot/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.devin});
      });

      test("put Devin's preamble below the shebang of a script", () {
        final script = translation([hookAsset(fs)]).files
            .singleWhere((c) => path.basename(c.file.path) == 'analyze.sh')
            .contents;
        final preamble = devinPreamble
            .replaceAll('__ROOT__', '"/plugins/vgv-wingspan"')
            .replaceAll(
              '__COMPAT__',
              '"$hooksRoot/${DevinTranslator.compatScript}"',
            );

        expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
      });

      test('copy nothing for a hook Devin cannot run', () {
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

      test('say nothing about a hook Devin runs as written', () {
        expect(notesOf([hookAsset(fs)]), isEmpty);
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
        expect(notes.single.reason, contains('names no subagent'));
      });

      test('say that a hook on an event Devin lacks is left out', () {
        final notes = notesOf([hookAsset(fs, event: 'Notification')]);

        expect(notes.single.subject, "vgv-wingspan's Notification hook");
        expect(
          notes.single.reason,
          'Devin has no Notification event, so it is left out',
        );
      });

      test('say that nothing a hook injects before a tool is read', () {
        final notes = notesOf([hookAsset(fs, event: 'PreToolUse')]);

        expect(notes.single.subject, 'the PreToolUse hooks');
        expect(notes.single.reason, contains('hears none of it'));
      });

      test('say that a handler running no shell command is left out', () {
        final notes = notesOf([
          hookAsset(
            fs,
            commands: const [HookCommand(type: 'prompt', command: 'hi')],
          ),
        ]);

        expect(notes.single.subject, '1 prompt handler(s)');
        expect(notes.single.reason, contains('drops every hook in a file'));
      });

      test('carry what could not be copied as intended', () {
        final hook = hookAsset(fs);
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
