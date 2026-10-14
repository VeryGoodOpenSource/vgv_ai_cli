import 'dart:convert';

import 'package:file/memory.dart';
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

    test('runs none of the hooks, as the default', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.hooks(
          pluginAssets(hooks: [hookAsset(fs)]),
          hooksRoot: fs.directory('/home/.copilot/hooks'),
        ),
        isNull,
      );
    });
  });
}
