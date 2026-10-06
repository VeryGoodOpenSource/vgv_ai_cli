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
        final json = translator.hooks(pluginAssets(hooks: hooks))!;
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

      test('substitute the plugin root the command points at', () {
        final registrations =
            events([hookAsset(fs)])['PostToolUse']! as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        expect(
          (commands.single! as Map)['command'],
          'bash /plugins/vgv-wingspan/hooks/scripts/analyze.sh',
        );
      });

      test('hand a script that watches edits the patched files', () {
        // Codex reports an edit as apply_patch and names the files it touched
        // in the response, not in a file_path, so the script gets them as
        // arguments instead. xargs turns the script's exit 2 into 123, which
        // is mapped back so the analyzer's output still blocks.
        final registrations =
            events([hookAsset(fs, matcher: 'Edit|Write')])['PostToolUse']!
                as List<Object?>;
        final commands =
            (registrations.single! as Map)['hooks']! as List<Object?>;

        const patchedFiles =
            r'(.cwd // ".") as $cwd | .tool_response | strings'
            r' | scan("(?m)^[AM] (.+)$") | .[0]'
            r' | if startswith("/") then . else $cwd + "/" + . end';

        expect(
          (commands.single! as Map)['command'],
          "jq -r '$patchedFiles' | tr '\\n' '\\0' | xargs -0"
          ' bash /plugins/vgv-wingspan/hooks/scripts/analyze.sh || exit 2',
        );
      });

      test('leave a script the payload names no files for alone', () {
        // Before the tool runs nothing has been edited yet, and a shell call
        // carries its command in the payload the same way on both harnesses.
        final before =
            events([
                  hookAsset(fs, event: 'PreToolUse', matcher: 'Edit|Write'),
                ])['PreToolUse']!
                as List<Object?>;
        final shell =
            events([hookAsset(fs, matcher: 'Bash')])['PostToolUse']!
                as List<Object?>;

        for (final registrations in [before, shell]) {
          final commands =
              (registrations.single! as Map)['hooks']! as List<Object?>;

          expect(
            (commands.single! as Map)['command'],
            'bash /plugins/vgv-wingspan/hooks/scripts/analyze.sh',
          );
        }
      });

      test('leave a handler that runs no shell command alone', () {
        // Codex takes an mcp_tool handler and Claude a prompt one. Neither
        // runs a shell command, so neither can take the files.
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
        expect(translator.hooks(pluginAssets()), isNull);
      });

      test('are null when no hook names a tool Codex has', () {
        // Codex reads files through the shell, so wingspan's Read|Glob|Grep
        // hook could never fire and nothing is left to write.
        expect(
          translator.hooks(
            pluginAssets(hooks: [hookAsset(fs, matcher: 'Read|Glob|Grep')]),
          ),
          isNull,
        );
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
