import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';

void main() {
  group('Harness', () {
    test('registry lists every known harness in reporting order', () {
      expect(Harness.values.map((harness) => harness.name), [
        'claude',
        'gemini',
        'codex',
        'opencode',
        'pi',
      ]);
    });

    test('every harness carries an executable and a display name', () {
      expect(Harness.values.map((harness) => harness.executable), [
        'claude',
        'gemini',
        'codex',
        'opencode',
        'pi',
      ]);
      expect(Harness.values.map((harness) => harness.displayName), [
        'Claude Code',
        'Gemini',
        'Codex',
        'OpenCode',
        'Pi',
      ]);
    });
  });
}
