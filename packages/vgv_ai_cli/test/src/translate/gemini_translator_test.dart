import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  late FileSystem fs;

  setUp(() => fs = MemoryFileSystem.test());

  group('GeminiTranslator', () {
    const translator = GeminiTranslator();

    test('configures Gemini', () {
      expect(translator.harness, Harness.gemini);
    });

    group('settings', () {
      test('declares each MCP server by name', () {
        final settings = jsonDecode(
          translator.settings(
            pluginAssets(
              mcpServers: [
                const LocalMCPServer(
                  name: 'dart',
                  command: 'dart',
                  args: ['mcp-server'],
                ),
              ],
            ),
          ),
        ) as Map<String, dynamic>;

        expect(settings['mcpServers'], {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        });
      });

      test("writes a remote server's headers as headers", () {
        final settings = jsonDecode(
          translator.settings(
            pluginAssets(
              mcpServers: [
                const RemoteMCPServer(
                  name: 'docs',
                  url: 'https://docs.example',
                  headers: {'X-Region': 'us'},
                ),
              ],
            ),
          ),
        ) as Map<String, dynamic>;

        expect(settings['mcpServers'], {
          'docs': {
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
        });
      });

      test('reads AGENTS.md without giving up its own GEMINI.md', () {
        final settings = jsonDecode(
          translator.settings(pluginAssets()),
        ) as Map<String, dynamic>;

        expect(settings['context'], {
          'fileName': ['AGENTS.md', 'GEMINI.md'],
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

    group('notes', () {
      test('report that nothing in its config runs a shell command, once', () {
        final notes = translator.notes(
          pluginAssets(hooks: [hookAsset(fs), hookAsset(fs)]),
        );

        expect(notes.single.subject, '2 hook(s)');
        expect(
          notes.single.reason,
          contains("nothing in Gemini's config runs one"),
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
