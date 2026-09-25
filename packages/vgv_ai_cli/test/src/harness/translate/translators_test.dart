import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/translate.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

import '_assets.dart';

/// Every translator, in reporting order.
const _translators = <HarnessTranslator>[
  ClaudeTranslator(),
  GeminiTranslator(),
  CodexTranslator(),
  OpenCodeTranslator(),
  PiTranslator(),
];

/// Every fragment the brick renders, so no translator reports one missing.
final _staged = StagedOutput({
  StagedFragment.claudeSettings.path: '{"enabledPlugins":{}}',
  StagedFragment.geminiSettings.path: '{"mcpServers":{}}',
  StagedFragment.codexConfig.path: '[mcp_servers.dart]\ncommand = "dart"\n',
  StagedFragment.openCodeConfig.path: '{"mcp":{}}',
  StagedFragment.piSettings.path: '{"skills":[]}',
});

void main() {
  late FileSystem fs;
  late Directory home;
  late PluginAssets assets;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);

    // Two plugins, merged the way install will merge them. `review` is
    // deliberately both an agent and a command name.
    assets = PluginAssets.merge([
      pluginAssets(
        skills: [skillAsset(fs, 'review'), skillAsset(fs, 'plan')],
        agents: [agentAsset('review'), agentAsset('planner')],
      ),
      pluginAssets(
        skills: [
          skillAsset(fs, 'testing'),
          skillAsset(fs, 'quiet', userInvocable: false),
        ],
        agents: [agentAsset('flutter-reviewer')],
        hooks: [
          hookAsset(fs, event: 'PreToolUse', matcher: 'Bash'),
          hookAsset(fs, plugin: 'vgv-ai-flutter-plugin'),
        ],
      ),
    ]);
  });

  for (final translator in _translators) {
    group(translator.harness.name, () {
      test('claims a unique path for every file it owns', () {
        // Two `own` changes to one path means one silently overwrites the
        // other.
        final paths = translator
            .translate(assets: assets, home: home, staged: _staged)
            .changes
            .where((c) => c.mode == ChangeMode.own)
            .map((c) => c.file.path)
            .toList();

        expect(paths.toSet(), hasLength(paths.length));
      });

      test('tags every change with the harness it configures', () {
        final changes = translator
            .translate(assets: assets, home: home, staged: _staged)
            .changes;

        expect(changes.map((c) => c.harness).toSet(), {translator.harness});
      });

      test('installs hooks only for Claude Code, reporting the rest once', () {
        final result = translator.translate(
          assets: assets,
          home: home,
          staged: _staged,
        );
        final hookNotes = result.notes.where((n) => n.subject.contains('hook'));

        if (translator.harness == Harness.claude) {
          expect(hookNotes, isEmpty);
        } else {
          expect(hookNotes.single.subject, '2 hook(s)');
          expect(hookNotes.single.reason, contains('only understand Claude'));
        }
        expect(
          result.changes.map((c) => c.file.path),
          everyElement(isNot(contains('hooks'))),
        );
      });

      test('writes nothing into the shared skills directory', () {
        // The skills are written once by SkillsTranslator; a per-harness copy
        // would be the duplication the shared path exists to avoid.
        final changes = translator
            .translate(assets: assets, home: home, staged: _staged)
            .changes;

        expect(
          changes.map((c) => c.file.path),
          everyElement(isNot(contains('/.agents/skills/'))),
        );
      });
    });
  }

  test('every translator covers a distinct harness', () {
    expect(_translators.map((t) => t.harness).toSet(), Harness.values.toSet());
  });

  test('the shared skills are planned once for all of them', () {
    final skills = const SkillsTranslator().translate(
      assets: assets,
      home: home,
    );

    final documents = skills.changes
        .where((c) => c.file.path.endsWith('SKILL.md'))
        .map((c) => c.file.path)
        .toList();

    expect(documents, hasLength(assets.skills.length));
    expect(documents.toSet(), hasLength(documents.length));
  });
}
