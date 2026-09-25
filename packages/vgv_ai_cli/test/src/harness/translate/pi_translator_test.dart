import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/pi_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

final _staged = StagedOutput({StagedFragment.piSettings.path: '{"skills":[]}'});

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  TranslationResult translate(PluginAssets assets, {StagedOutput? staged}) =>
      const PiTranslator().translate(
        assets: assets,
        home: home,
        staged: staged ?? _staged,
      );

  PlannedChange at(TranslationResult result, String suffix) =>
      result.changes.firstWhere((c) => c.file.path.endsWith(suffix));

  group('PiTranslator', () {
    test('configures Pi', () {
      expect(const PiTranslator().harness, Harness.pi);
    });

    test('merges the staged settings fragment', () {
      final change = at(translate(pluginAssets()), 'settings.json');

      expect(change.file.path, '/home/dev/.pi/agent/settings.json');
      expect(change.mode, ChangeMode.mergeJson);
    });

    test('reports an absent settings fragment', () {
      expect(
        translate(
          pluginAssets(),
          staged: const StagedOutput({}),
        ).notes.single.subject,
        StagedFragment.piSettings.path,
      );
    });

    test('writes no agents, since Pi has no subagents', () {
      final result = translate(pluginAssets(agents: [agentAsset('reviewer')]));

      expect(
        result.changes.map((c) => c.file.path),
        everyElement(isNot(contains('reviewer'))),
      );
      expect(result.notes, isEmpty);
    });

    test('writes each invocable skill as a prompt', () {
      final result = translate(pluginAssets(skills: [skillAsset(fs, 'plan')]));

      expect(
        at(result, 'plan.md').file.path,
        '/home/dev/.pi/agent/prompts/plan.md',
      );
      expect(at(result, 'plan.md').contents, '# Body\n');
    });

    test('writes no prompt for a skill that is not user invocable', () {
      final result = translate(
        pluginAssets(
          skills: [skillAsset(fs, 'elements-of-style', userInvocable: false)],
        ),
      );

      expect(
        result.changes.map((c) => c.file.path),
        isNot(contains(contains('prompts/'))),
      );
    });
  });
}
