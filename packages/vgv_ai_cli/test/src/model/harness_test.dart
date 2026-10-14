import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('Harness', () {
    test('lists every known harness in reporting order', () {
      expect(Harness.values.map((harness) => harness.name), [
        'claude',
        'gemini',
        'codex',
        'opencode',
        'pi',
        'copilot',
        'antigravity',
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

    test('resolves each config directory under home', () {
      final home = MemoryFileSystem.test().directory('/home/dev');

      expect(
        {
          for (final harness in Harness.values)
            harness: harness.configDirectory(home).path,
        },
        {
          Harness.claude: '/home/dev/.claude',
          Harness.gemini: '/home/dev/.gemini',
          Harness.codex: '/home/dev/.codex',
          Harness.opencode: '/home/dev/.config/opencode',
          Harness.pi: '/home/dev/.pi/agent',
          Harness.copilot: '/home/dev/.copilot',
          Harness.antigravity: '/home/dev/.gemini/config',
        },
      );
    });
  });
}
