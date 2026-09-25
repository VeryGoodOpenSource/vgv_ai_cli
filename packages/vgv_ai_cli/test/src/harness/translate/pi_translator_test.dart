import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/pi_translator.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

import '_assets.dart';

void main() {
  group('PiTranslator', () {
    const translator = PiTranslator();

    test('configures Pi', () {
      expect(translator.harness, Harness.pi);
    });

    test('has no settings, since Pi reads the shared skills natively', () {
      expect(translator.settings(pluginAssets()), isNull);
    });

    test('spells nothing else, since Pi reads prompts as written', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.agent(agentAsset('reviewer'), instructions: 'x'),
        isEmpty,
      );
      expect(translator.command(skillAsset(fs, 'plan')), isEmpty);
    });

    test('reports that hooks are Claude-only', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.notes(pluginAssets(hooks: [hookAsset(fs)])).single.reason,
        contains('Pi gets none for now'),
      );
    });

    test('reports the agents and MCP servers it cannot configure', () {
      final notes = translator.notes(
        pluginAssets(
          agents: [agentAsset('reviewer'), agentAsset('planner')],
          mcpServers: [const LocalMCPServer(name: 'dart', command: 'dart')],
        ),
      );

      expect(notes.map((note) => note.subject), [
        '2 agent(s)',
        '1 MCP server(s)',
      ]);
    });

    test('reports nothing when the plugins bring nothing Pi lacks', () {
      expect(translator.notes(pluginAssets()), isEmpty);
    });
  });
}
