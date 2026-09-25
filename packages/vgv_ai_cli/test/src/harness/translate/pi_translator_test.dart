import 'dart:convert';

import 'package:file/memory.dart';
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

    test('points its settings at the shared skills', () {
      expect(
        jsonDecode(translator.settings(pluginAssets(), skillsRoot: '/skills')),
        {
          'skills': ['/skills'],
        },
      );
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
  });
}
