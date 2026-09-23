import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/harness/translate/gemini_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

const StagedOutput _staged = {StagedPaths.geminiSettings: '{"mcpServers":{}}'};

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  TranslationResult translate(PluginAssets assets, {StagedOutput? staged}) =>
      const GeminiTranslator().translate(
        assets: assets,
        home: home,
        staged: staged ?? _staged,
      );

  PlannedChange at(TranslationResult result, String suffix) =>
      result.changes.firstWhere((c) => c.file.path.endsWith(suffix));

  group('GeminiTranslator', () {
    test('configures Gemini', () {
      expect(const GeminiTranslator().harness, Harness.gemini);
    });

    test('merges the staged settings fragment', () {
      final change = at(translate(pluginAssets()), '.gemini/settings.json');

      expect(change.mode, ChangeMode.mergeJson);
      expect(change.harness, Harness.gemini);
    });

    test('reports an absent settings fragment', () {
      final result = translate(pluginAssets(), staged: const {});

      expect(result.changes, isEmpty);
      expect(result.notes.single.subject, StagedPaths.geminiSettings);
    });

    group('agents', () {
      test('writes them flat, since the loader reads no subdirectories', () {
        final result = translate(
          pluginAssets(agents: [agentAsset('code-reviewer')]),
        );

        expect(
          at(result, 'code-reviewer.md').file.path,
          '/home/dev/.gemini/agents/code-reviewer.md',
        );
      });

      test('writes frontmatter the loader requires and can parse', () {
        final result = translate(
          pluginAssets(agents: [agentAsset('reviewer')]),
        );

        final parsed = Frontmatter.parse(
          at(result, 'reviewer.md').contents,
          path: 'reviewer.md',
        );

        expect(parsed.name, 'reviewer');
        expect(parsed.description, 'reviews code');
      });

      test('reports a name the loader would refuse instead of writing it', () {
        // Gemini's schema accepts ^[a-z0-9_-]+$; anything else is not loaded,
        // so writing the file would look like success and do nothing.
        final result = translate(
          pluginAssets(agents: [agentAsset('Code Reviewer!')]),
        );

        expect(
          result.changes.map((c) => c.file.path),
          isNot(contains(contains('agents/'))),
        );
        expect(result.notes.single.subject, 'agent Code Reviewer!');
      });
    });

    group('commands', () {
      test('writes TOML that parses back as TOML', () {
        // Bodies are whole markdown documents full of quotes and backticks.
        final result = translate(
          pluginAssets(
            skills: [
              skillAsset(
                fs,
                'green-gate',
                body: 'Run `dart analyze`.\nHe said "go".\n',
              ),
            ],
          ),
        );

        final parsed = TomlDocument.parse(
          at(result, 'green-gate.toml').contents,
        ).toMap();

        expect(parsed['description'], 'what it does');
        expect(parsed['prompt'], contains('He said "go".'));
      });

      test('rewrites the argument placeholder to Gemini syntax', () {
        final result = translate(
          pluginAssets(
            skills: [skillAsset(fs, 'plan', body: r'Plan $ARGUMENTS now.')],
          ),
        );

        final contents = at(result, 'plan.toml').contents;

        expect(contents, contains('{{args}}'));
        expect(contents, isNot(contains(r'$ARGUMENTS')));
      });

      test('writes no command for a skill that is not user invocable', () {
        final result = translate(
          pluginAssets(
            skills: [skillAsset(fs, 'elements-of-style', userInvocable: false)],
          ),
        );

        expect(
          result.changes.map((c) => c.file.path),
          isNot(contains(contains('commands/'))),
        );
      });
    });
  });
}
