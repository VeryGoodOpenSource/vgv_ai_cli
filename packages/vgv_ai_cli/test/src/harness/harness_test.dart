import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';

void main() {
  group('Harness', () {
    test('lists every known harness in reporting order', () {
      expect(Harness.values.map((harness) => harness.name), [
        'claude',
        'gemini',
        'codex',
        'opencode',
        'pi',
      ]);
    });

    test('gives every harness a unique executable', () {
      final executables = Harness.values.map((harness) => harness.executable);

      expect(executables.toSet(), hasLength(Harness.values.length));
      expect(executables, everyElement(isNotEmpty));
    });

    test('gives every harness a display name', () {
      expect(
        Harness.values.map((harness) => harness.displayName),
        everyElement(isNotEmpty),
      );
      expect(Harness.opencode.displayName, 'OpenCode');
      expect(Harness.opencode.executable, 'opencode');
    });
  });
}
