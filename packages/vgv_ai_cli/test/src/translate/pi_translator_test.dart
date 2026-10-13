import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

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
        const HarnessFields(),
      );
      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    test('runs none of the hooks', () {
      expect(translator.runsHooks, isFalse);
    });

    test('spells no hooks and no files beside them, as the default', () {
      final hooksRoot = MemoryFileSystem.test().directory('/home/.pi/hooks');

      expect(translator.hooks(pluginAssets(), hooksRoot: hooksRoot), isNull);
      expect(
        translator.hookFiles(pluginAssets(), hooksRoot: hooksRoot),
        isEmpty,
      );
    });

    test('reports that nothing in its config runs a shell command', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.notes(pluginAssets(hooks: [hookAsset(fs)])).single.reason,
        contains("nothing in Pi's config runs one"),
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
