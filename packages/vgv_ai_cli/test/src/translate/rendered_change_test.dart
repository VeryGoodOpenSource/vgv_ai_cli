import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

void main() {
  final home = MemoryFileSystem.test().directory('/home/dev');

  PlannedChange plan(String path) =>
      renderedChange(path, contents: 'x', home: home);

  group('renderedChange', () {
    test('lands a folder in its harness config directory', () {
      final change = plan('opencode/agent/review.md');

      expect(change.file.path, '/home/dev/.config/opencode/agent/review.md');
      expect(change.harness, Harness.opencode);
      expect(change.contents, 'x');
    });

    test('merges root JSON, TOML and markdown', () {
      expect(plan('gemini/settings.json').mode, ChangeMode.mergeJson);
      expect(plan('codex/config.toml').mode, ChangeMode.mergeToml);
      expect(plan('gemini/AGENTS.md').mode, ChangeMode.mergeMarkdown);
    });

    test('names the instructions section, and only for markdown', () {
      expect(plan('gemini/AGENTS.md').section, instructionsSection);
      expect(plan('gemini/settings.json').section, isNull);
      expect(plan('codex/agents/review.toml').section, isNull);
    });

    test('owns anything in a subdirectory, whatever its type', () {
      expect(plan('codex/agents/review.toml').mode, ChangeMode.own);
      expect(plan('pi/prompts/plan.md').mode, ChangeMode.own);
    });

    test('rejects a folder no harness is named after', () {
      expect(() => plan('cursor/settings.json'), throwsArgumentError);
    });
  });
}
