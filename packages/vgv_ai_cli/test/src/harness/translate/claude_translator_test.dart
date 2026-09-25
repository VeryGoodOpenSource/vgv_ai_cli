import 'dart:convert';

import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/claude_translator.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

import '_assets.dart';

void main() {
  group('ClaudeTranslator', () {
    const translator = ClaudeTranslator();

    test('configures Claude Code', () {
      expect(translator.harness, Harness.claude);
    });

    test('points Claude Code at the marketplace and enables both plugins', () {
      final settings = jsonDecode(
        translator.settings(pluginAssets(), skillsRoot: '/skills'),
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

    test('spells no agents or commands, which the marketplace supplies', () {
      final fs = MemoryFileSystem.test();

      expect(
        translator.agent(agentAsset('reviewer'), instructions: 'x'),
        isEmpty,
      );
      expect(translator.command(skillAsset(fs, 'plan')), isEmpty);
    });

    test('reports nothing, since the plugins run here as written', () {
      final fs = MemoryFileSystem.test();

      expect(translator.notes(pluginAssets(hooks: [hookAsset(fs)])), isEmpty);
    });
  });
}
