import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/claude_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/staged_output.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

const _settings = '{"enabledPlugins":{"vgv-wingspan@vgv":true}}';

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/home/dev')..createSync(recursive: true);
  });

  SkillAsset skillNamed(String name) => SkillAsset(
    name: name,
    description: 'd',
    body: 'b',
    userInvocable: true,
    allowedTools: const [],
    portableFrontmatter: {'name': name},
    directory: fs.directory('/plugins/$name'),
  );

  PluginAssets assets({List<SkillAsset> skills = const []}) => PluginAssets(
    skills: skills,
    agents: const [
      AgentAsset(name: 'reviewer', description: 'd', body: 'b', skills: []),
    ],
    mcpServers: const [],
  );

  group('ClaudeTranslator', () {
    test('configures Claude Code', () {
      expect(const ClaudeTranslator().harness, Harness.claude);
    });

    test('merges the marketplace settings into the user settings', () {
      final result = const ClaudeTranslator().translate(
        assets: assets(),
        home: home,
        staged: StagedOutput({StagedFragment.claudeSettings.path: _settings}),
      );

      final change = result.changes.single;
      expect(change.file.path, '/home/dev/.claude/settings.json');
      expect(change.mode, ChangeMode.mergeJson);
      expect(change.contents, _settings);
      expect(change.harness, Harness.claude);
      expect(result.notes, isEmpty);
    });

    test('copies no skills, because the marketplace supplies them', () {
      // A second copy would drift from the marketplace one on the next
      // plugin release.
      final result = const ClaudeTranslator().translate(
        assets: assets(skills: [skillNamed('testing')]),
        home: home,
        staged: StagedOutput({StagedFragment.claudeSettings.path: _settings}),
      );

      expect(
        result.changes.map((c) => c.file.path),
        everyElement(endsWith('settings.json')),
      );
    });

    test('reports the absent fragment rather than writing an empty one', () {
      // No fragment means the harness was not selected when the brick ran.
      final result = const ClaudeTranslator().translate(
        assets: assets(),
        home: home,
        staged: const StagedOutput({}),
      );

      expect(result.changes, isEmpty);
      expect(result.notes.single.subject, StagedFragment.claudeSettings.path);
      expect(
        result.notes.single.reason,
        contains('/home/dev/.claude/settings.json'),
      );
    });
  });
}
