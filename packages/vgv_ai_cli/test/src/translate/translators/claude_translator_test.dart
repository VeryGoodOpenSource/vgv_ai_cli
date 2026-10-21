import 'dart:convert';

import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

import '../_assets.dart';

void main() {
  group(ClaudeTranslator, () {
    const translator = ClaudeTranslator();

    test('configures Claude Code', () {
      expect(translator.harness, Harness.claude);
    });

    test('points Claude Code at the marketplace and enables both plugins', () {
      final settings = jsonDecode(
        translator.settings(pluginAssets(plugins: vgvPlugins)),
      );

      expect(settings, {
        'extraKnownMarketplaces': {
          'very-good-claude-code-marketplace': {
            'source': {
              'source': 'github',
              'repo': 'VeryGoodOpenSource/very-good-claude-code-marketplace',
            },
          },
        },
        'enabledPlugins': {
          'vgv-wingspan@very-good-claude-code-marketplace': true,
          'vgv-ai-flutter-plugin@very-good-claude-code-marketplace': true,
        },
      });
    });

    test('enables only the plugins the assets came from', () {
      final wingspan = vgvPlugins.first;
      final settings = jsonDecode(
        translator.settings(pluginAssets(plugins: [wingspan])),
      ) as Map<String, dynamic>;

      expect(settings['enabledPlugins'], {
        '${wingspan.name}@very-good-claude-code-marketplace': true,
      });
    });

    test('spells no agents or commands, which the marketplace supplies', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.agent(agentAsset('reviewer'), instructions: 'x'),
        const HarnessFields(),
      );
      expect(translator.command(skillAsset(fs, 'plan')), const HarnessFields());
    });

    test('writes nothing for the hooks, which the plugin system runs', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.hooks(
          pluginAssets(hooks: [hookAsset(fs)]),
          hooksRoot: fs.directory('/home/.claude/hooks'),
        ),
        const HookTranslation(),
      );
      expect(translator.notes(pluginAssets(hooks: [hookAsset(fs)])), isEmpty);
    });
  });
}
