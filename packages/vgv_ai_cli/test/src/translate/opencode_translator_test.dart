import 'dart:convert';

import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '_assets.dart';

void main() {
  group('OpenCodeTranslator', () {
    const translator = OpenCodeTranslator();
    final home = MemoryFileSystem.test().directory('/home/dev');

    test('configures OpenCode', () {
      expect(translator.harness, Harness.opencode);
    });

    test('declares that it runs no hooks, which the notes read', () {
      expect(translator.runsHooks, isFalse);
    });

    test('types each MCP server and folds its args into the command', () {
      final settings = jsonDecode(
        translator.settings(
          home: home,
          pluginAssets(
            mcpServers: [
              const LocalMCPServer(
                name: 'dart',
                command: 'dart',
                args: ['mcp-server'],
                env: {'TOKEN': 'x'},
              ),
              const LocalMCPServer(name: 'bare', command: 'bare'),
              const RemoteMCPServer(
                name: 'docs',
                url: 'https://docs.example',
                headers: {'X-Region': 'us'},
              ),
              const RemoteMCPServer(name: 'open', url: 'https://open.example'),
            ],
          ),
        ),
      );

      expect(settings, {
        r'$schema': 'https://opencode.ai/config.json',
        'mcp': {
          'dart': {
            'type': 'local',
            'command': ['dart', 'mcp-server'],
            'environment': {'TOKEN': 'x'},
          },
          'bare': {
            'type': 'local',
            'command': ['bare'],
          },
          'docs': {
            'type': 'remote',
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
          'open': {'type': 'remote', 'url': 'https://open.example'},
        },
        'instructions': ['AGENTS.md'],
      });
    });

    test('marks an agent as a subagent so it is delegated to', () {
      final fields = translator.agent(
        agentAsset('reviewer'),
        instructions: 'x',
      );

      expect(frontmatterValues(fields.frontmatter), {
        'description': 'reviews code',
        'mode': 'subagent',
      });
    });

    test('gives a command its description as frontmatter', () {
      final fs = MemoryFileSystem.test();
      final fields = translator.command(skillAsset(fs, 'plan'));

      expect(frontmatterValues(fields.frontmatter), {
        'description': 'what it does',
      });
    });

    test('reports that nothing in its config runs a shell command', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.notes(pluginAssets(hooks: [hookAsset(fs)])).single.reason,
        contains("nothing in OpenCode's config runs one"),
      );
    });
  });
}
