import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/harness/translate/opencode_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

const StagedOutput _staged = {StagedPaths.openCodeConfig: '{"mcp":{}}'};

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  TranslationResult translate(PluginAssets assets, {StagedOutput? staged}) =>
      const OpenCodeTranslator().translate(
        assets: assets,
        home: home,
        staged: staged ?? _staged,
      );

  PlannedChange at(TranslationResult result, String suffix) =>
      result.changes.firstWhere((c) => c.file.path.endsWith(suffix));

  group('OpenCodeTranslator', () {
    test('configures OpenCode', () {
      expect(const OpenCodeTranslator().harness, Harness.opencode);
    });

    test('merges the staged config under the XDG config root', () {
      final change = at(translate(pluginAssets()), 'opencode.json');

      expect(change.file.path, '/home/dev/.config/opencode/opencode.json');
      expect(change.mode, ChangeMode.mergeJson);
    });

    test('reports an absent config fragment', () {
      expect(
        translate(pluginAssets(), staged: const {}).notes.single.subject,
        StagedPaths.openCodeConfig,
      );
    });

    group('agents', () {
      test('marks them as subagents so they are delegated to', () {
        final result = translate(
          pluginAssets(agents: [agentAsset('reviewer')]),
        );

        final parsed = Frontmatter.parse(
          at(result, 'reviewer.md').contents,
          path: 'reviewer.md',
        );

        expect(parsed.config.string('mode'), 'subagent');
        expect(parsed.config.string('description'), 'reviews code');
      });

      test('uses the singular directory the maintainers use', () {
        final result = translate(
          pluginAssets(agents: [agentAsset('reviewer')]),
        );

        expect(
          at(result, 'reviewer.md').file.path,
          '/home/dev/.config/opencode/agent/reviewer.md',
        );
      });
    });

    group('commands', () {
      test('writes frontmatter that parses back', () {
        final result = translate(
          pluginAssets(skills: [skillAsset(fs, 'green-gate')]),
        );

        final change = at(result, 'green-gate.md');
        final parsed = Frontmatter.parse(change.contents, path: 'c.md');

        expect(
          change.file.path,
          '/home/dev/.config/opencode/command/green-gate.md',
        );
        expect(parsed.config.string('description'), 'what it does');
        expect(parsed.body, contains('# Body'));
      });

      test('writes no command for a skill that is not user invocable', () {
        final result = translate(
          pluginAssets(
            skills: [skillAsset(fs, 'elements-of-style', userInvocable: false)],
          ),
        );

        expect(
          result.changes.map((c) => c.file.path),
          isNot(contains(contains('command/'))),
        );
      });
    });
  });
}
