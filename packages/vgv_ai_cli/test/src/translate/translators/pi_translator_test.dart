import 'dart:convert';

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

import '../_assets.dart';

void main() {
  group(PiTranslator, () {
    const translator = PiTranslator();

    test('configures Pi', () {
      expect(translator.harness, Harness.pi);
    });

    test('declares each MCP server by name', () {
      final settings = translator.settings(
        pluginAssets(
          mcpServers: [
            const LocalMCPServer(
              name: 'dart',
              command: 'dart',
              args: ['mcp-server'],
            ),
            const RemoteMCPServer(
              name: 'docs',
              url: 'https://docs.example',
              headers: {'X-Region': 'us'},
            ),
          ],
        ),
      );

      expect(jsonDecode(settings), {
        'mcpServers': {
          'dart': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
          'docs': {
            'url': 'https://docs.example',
            'headers': {'X-Region': 'us'},
          },
        },
      });
    });

    test('declares no MCP servers when the plugins bring none', () {
      expect(jsonDecode(translator.settings(pluginAssets())), {
        'mcpServers': <String, Object?>{},
      });
    });

    test('spells nothing else, since Pi reads prompts as written', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.agent(agentAsset('reviewer'), instructions: 'x'),
        const HarnessFields(),
      );
      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    test('runs none of the hooks, as the default', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.hooks(
          pluginAssets(hooks: [hookAsset(fs)]),
          hooksRoot: fs.directory('/home/.pi/hooks'),
        ),
        isNull,
      );
    });

    test('copies none of the hook scripts, as the default', () {
      expect(translator.scripts, isNull);
    });

    test('reports the agents it cannot configure', () {
      final notes = translator.notes(
        pluginAssets(
          agents: [agentAsset('reviewer'), agentAsset('planner')],
          mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
        ),
      );

      expect(notes.map((note) => note.subject), ['2 agent(s)']);
    });

    test('reports nothing when the plugins bring nothing Pi lacks', () {
      expect(translator.notes(pluginAssets()), isEmpty);
    });
  });
}
