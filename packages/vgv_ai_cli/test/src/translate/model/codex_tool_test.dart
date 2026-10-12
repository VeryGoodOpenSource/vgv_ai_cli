import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

void main() {
  group('CodexTool', () {
    test("names Codex's own tool alongside Claude's for a file edit", () {
      expect(CodexTool.codexNamesOf('Edit'), ['Edit', 'apply_patch']);
      expect(CodexTool.codexNamesOf('Write'), ['Write', 'apply_patch']);
    });

    test('names the shell for a tool Codex reads files with', () {
      // Codex has no Read, Glob or Grep: it reads through the shell.
      for (final tool in [CodexTool.read, CodexTool.glob, CodexTool.grep]) {
        expect(CodexTool.codexNamesOf(tool.claude), ['Bash']);
      }
    });

    test('carries over a name both harnesses spell the same way', () {
      expect(CodexTool.codexNamesOf('Bash'), ['Bash']);
      expect(CodexTool.codexNamesOf('mcp__x__y'), ['mcp__x__y']);
    });
  });
}
