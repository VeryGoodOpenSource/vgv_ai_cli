import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
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

  group('GeminiTranslator', () {
    const translator = GeminiTranslator();

    test('configures Gemini', () {
      expect(translator.harness, Harness.gemini);
    });

    test('declares that it runs the hooks, which the notes read', () {
      expect(translator.runsHooks, isTrue);
    });

    group('settings', () {
      /// The settings [assets] translate to.
      Map<String, dynamic> settings(PluginAssets assets) =>
          jsonDecode(translator.settings(assets, home: home))
              as Map<String, dynamic>;

      test('declares each MCP server by name', () {
        final found = settings(
          pluginAssets(
            mcpServers: [
              const LocalMCPServer(
                name: 'dart',
                command: 'dart',
                args: ['mcp-server'],
              ),
            ],
          ),
        );

        expect(found['mcpServers'], {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        });
      });

      test("writes a remote server's headers as headers", () {
        final found = settings(
          pluginAssets(
            mcpServers: [
              const RemoteMCPServer(
                name: 'docs',
                url: 'https://docs.example',
                headers: {'X-Region': 'us'},
              ),
            ],
          ),
        );

        expect(found['mcpServers'], {
          'docs': {
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
        });
      });

      test('reads AGENTS.md without giving up its own GEMINI.md', () {
        expect(settings(pluginAssets())['context'], {
          'fileName': ['AGENTS.md', 'GEMINI.md'],
        });
      });

      test('carry no hooks key when the plugins ship no hooks', () {
        expect(settings(pluginAssets()), isNot(contains('hooks')));
      });

      group('hooks', () {
        /// The registrations [hooks] translate to, under Gemini's event.
        List<Map<String, Object?>> entries(
          List<HookAsset> hooks,
          String event,
        ) {
          final events = settings(pluginAssets(hooks: hooks))['hooks'] as Map;
          return (events[event]! as List<Object?>).cast();
        }

        test("sit under Gemini's name for each event", () {
          final events =
              settings(
                    pluginAssets(
                      hooks: [
                        hookAsset(fs, event: 'PreToolUse'),
                        hookAsset(fs),
                        hookAsset(fs, event: 'SessionStart'),
                        hookAsset(fs, event: 'Stop'),
                      ],
                    ),
                  )['hooks']
                  as Map;

          expect(events.keys, [
            'BeforeTool',
            'AfterTool',
            'SessionStart',
            'AfterAgent',
          ]);
        });

        test('point each command at the copy, timed in milliseconds', () {
          final entry = entries([hookAsset(fs)], 'AfterTool').single;

          expect(entry, {
            'hooks': [
              {
                'type': 'command',
                'command': [
                  'bash "/home/dev/.gemini/hooks/vgv-wingspan"',
                  'hooks/scripts/analyze.sh',
                ].join('/'),
                'timeout': 30000,
              },
            ],
          });
        });

        test('leave a command with no timeout without one', () {
          final entry = entries([
            hookAsset(
              fs,
              commands: const [HookCommand(type: 'command', command: 'a.sh')],
            ),
          ], 'AfterTool').single;

          expect((entry['hooks']! as List).single, {
            'type': 'command',
            'command': 'a.sh',
          });
        });

        test('name the tools a matcher names the way Gemini does', () {
          final entry = entries([
            hookAsset(fs, matcher: 'Edit|Write'),
          ], 'AfterTool').single;

          expect(entry['matcher'], 'replace|write_file');
        });

        test('spell an MCP tool the way Gemini names it', () {
          final entry = entries([
            hookAsset(
              fs,
              event: 'PreToolUse',
              matcher: 'Bash|mcp__.*very-good-cli__.*',
            ),
          ], 'BeforeTool').single;

          expect(entry['matcher'], 'run_shell_command|mcp_.*very-good-cli_.*');
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
          ], 'AfterTool').single;

          expect((entry['hooks']! as List).single, {
            'type': 'command',
            'command': 'a.sh',
          });
        });

        test('leave out a hook an agent declares for itself', () {
          final found = settings(
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

          expect(found, isNot(contains('hooks')));
        });

        test('leave out a hook on an event Gemini has no name for', () {
          final found = settings(
            pluginAssets(hooks: [hookAsset(fs, event: 'SubagentStop')]),
          );

          expect(found, isNot(contains('hooks')));
        });
      });
    });

    test('gives an agent the frontmatter the loader requires', () {
      final fields = translator.agent(
        agentAsset('reviewer', description: 'reviews: code'),
        instructions: 'x',
      );

      expect(frontmatterValues(fields.frontmatter), {
        'name': 'reviewer',
        'description': 'reviews: code',
      });
    });

    group('commands', () {
      test('are TOML that parses back', () {
        final toml = translator
            .command(skillAsset(fs, 'plan', body: 'Say "hi" to `you` \\n\n'))
            .toml!;

        expect(TomlDocument.parse(toml).toMap(), {
          'description': 'what it does',
          'prompt': 'Say "hi" to `you` \\n\n',
        });
      });

      test('spell the argument placeholder the Gemini way', () {
        final toml = translator
            .command(skillAsset(fs, 'plan', body: r'Plan $ARGUMENTS now.'))
            .toml!;

        expect(
          TomlDocument.parse(toml).toMap()['prompt'],
          'Plan {{args}} now.',
        );
      });
    });

    group('hookFiles', () {
      List<PlannedChange> files(List<HookAsset> hooks) => translator.hookFiles(
        pluginAssets(hooks: hooks),
        hooksRoot: fs.directory('/home/dev/.gemini/hooks'),
      );

      test("copy the plugin's hooks folder under its name, registry aside", () {
        final changes = files([hookAsset(fs)]);

        expect(changes.map((c) => c.file.path), [
          '/home/dev/.gemini/hooks/vgv-wingspan/hooks/scripts/analyze.sh',
          '/home/dev/.gemini/hooks/vgv-wingspan/hooks/scripts/common.sh',
        ]);
        expect(changes.map((c) => c.harness).toSet(), {Harness.gemini});
      });

      test(
        "put Gemini's preamble below the shebang of a script a hook runs",
        () {
          final script = files([hookAsset(fs)])
              .singleWhere((c) => path.basename(c.file.path) == 'analyze.sh')
              .contents;
          final preamble = GeminiTranslator.preamble.replaceAll(
            '__ROOT__',
            '"/plugins/vgv-wingspan"',
          );

          expect(script, '#!/bin/bash\n${preamble}source common.sh\necho hi\n');
        },
      );

      test('copy nothing for a hook Gemini cannot run', () {
        expect(
          files([hookAsset(fs, matcher: 'Bash', agent: 'flutter-reviewer')]),
          isEmpty,
        );
        expect(files([hookAsset(fs, event: 'SubagentStop')]), isEmpty);
      });
    });

    group('notes', () {
      test('say nothing about hooks Gemini runs as declared', () {
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

      test('say that a hook on an event Gemini lacks is left out', () {
        final notes = translator.notes(
          pluginAssets(hooks: [hookAsset(fs, event: 'SubagentStop')]),
        );

        expect(notes.single.subject, "vgv-wingspan's SubagentStop hook");
        expect(
          notes.single.reason,
          'Gemini has no SubagentStop event, so it is left out',
        );
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

      test('carry what could not be copied as intended', () {
        final hook = hookAsset(fs);
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
