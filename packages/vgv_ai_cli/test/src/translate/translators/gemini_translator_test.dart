import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '../_assets.dart';

void main() {
  group(GeminiTranslator, () {
    late FileSystem fs;

    setUp(() => fs = MemoryFileSystem.test());

    const translator = GeminiTranslator();

    test('configures Gemini', () {
      expect(translator.harness, Harness.gemini);
    });

    test('runs none of the hooks', () {
      expect(
        translator.hooks(
          pluginAssets(hooks: [hookAsset(fs)]),
          hooksRoot: fs.directory('/home/.gemini/hooks'),
        ),
        isNull,
      );
    });

    group('settings', () {
      test('declares each MCP server by name', () {
        final settings = translator.settings(
          pluginAssets(
            mcpServers: [
              const LocalMCPServer(
                name: 'dart',
                command: 'dart',
                args: ['mcp-server'],
              ),
            ],
          ),
          plugins: vgvPlugins,
        );

        expect(
          jsonDecode(settings),
          containsPair('mcpServers', {
            'dart': {
              'command': 'dart',
              'args': ['mcp-server'],
            },
          }),
        );
      });

      test("writes a remote server's headers as headers", () {
        final settings = translator.settings(
          pluginAssets(
            mcpServers: [
              const RemoteMCPServer(
                name: 'docs',
                url: 'https://docs.example',
                headers: {'X-Region': 'us'},
              ),
            ],
          ),
          plugins: vgvPlugins,
        );

        expect(
          jsonDecode(settings),
          containsPair('mcpServers', {
            'docs': {
              'url': 'https://docs.example',
              'headers': {'X-Region': 'us'},
            },
          }),
        );
      });

      test('reads AGENTS.md without giving up its own GEMINI.md', () {
        expect(
          jsonDecode(translator.settings(pluginAssets(), plugins: vgvPlugins)),
          containsPair('context', {
            'fileName': ['AGENTS.md', 'GEMINI.md'],
          }),
        );
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

    test('reports nothing itself', () {
      expect(
        translator.notes(
          pluginAssets(hooks: [hookAsset(fs)], agents: [agentAsset('r')]),
        ),
        isEmpty,
      );
    });
  });
}
