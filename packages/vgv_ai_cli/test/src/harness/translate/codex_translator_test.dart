import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/codex_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

final _staged = StagedOutput({
  StagedFragment.codexConfig.path: '[mcp_servers.dart]\ncommand = "dart"\n',
});

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  TranslationResult translate(PluginAssets assets, {StagedOutput? staged}) =>
      const CodexTranslator().translate(
        assets: assets,
        home: home,
        staged: staged ?? _staged,
      );

  PlannedChange at(TranslationResult result, String suffix) =>
      result.changes.firstWhere((c) => c.file.path.endsWith(suffix));

  group('CodexTranslator', () {
    test('configures Codex', () {
      expect(const CodexTranslator().harness, Harness.codex);
    });

    test('merges the staged config as TOML', () {
      final change = at(translate(pluginAssets()), '.codex/config.toml');

      expect(change.mode, ChangeMode.mergeToml);
      expect(change.harness, Harness.codex);
    });

    test('reports an absent config fragment', () {
      expect(
        translate(
          pluginAssets(),
          staged: const StagedOutput({}),
        ).notes.single.subject,
        StagedFragment.codexConfig.path,
      );
    });

    group('agents', () {
      test('writes the three keys the loader needs, as parseable TOML', () {
        // A role missing description is loaded then dropped with a warning,
        // so all three are required in practice.
        final result = translate(
          pluginAssets(agents: [agentAsset('reviewer')]),
        );

        final parsed = TomlDocument.parse(at(result, 'reviewer.toml').contents)
            .toMap();

        expect(parsed['name'], 'reviewer');
        expect(parsed['description'], 'reviews code');
        expect(parsed['developer_instructions'], contains('You review code.'));
      });

      test('survives a body full of quotes, backticks and backslashes', () {
        final result = translate(
          pluginAssets(
            agents: [
              agentAsset(
                'reviewer',
                body: r'Run `dart analyze`. He said "go" at C:\dart.',
              ),
            ],
          ),
        );

        final parsed = TomlDocument.parse(at(result, 'reviewer.toml').contents)
            .toMap();

        expect(
          parsed['developer_instructions'],
          contains(r'He said "go" at C:\dart.'),
        );
      });

      test('points at the shared skills rather than inlining them', () {
        final result = translate(
          pluginAssets(
            agents: [
              agentAsset('reviewer', skills: ['testing']),
            ],
          ),
        );

        final parsed = TomlDocument.parse(at(result, 'reviewer.toml').contents)
            .toMap();

        expect(
          parsed['developer_instructions'],
          contains('/home/dev/.agents/skills'),
        );
      });
    });

    group('prompts', () {
      test('writes them flat, since Codex reads no subdirectories', () {
        final result = translate(
          pluginAssets(skills: [skillAsset(fs, 'green-gate')]),
        );

        expect(
          at(result, 'green-gate.md').file.path,
          '/home/dev/.codex/prompts/green-gate.md',
        );
      });

      test('keeps the Claude argument placeholder, which Codex also reads', () {
        final result = translate(
          pluginAssets(
            skills: [skillAsset(fs, 'plan', body: r'Plan $ARGUMENTS.')],
          ),
        );

        expect(at(result, 'plan.md').contents, contains(r'$ARGUMENTS'));
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
  });
}
