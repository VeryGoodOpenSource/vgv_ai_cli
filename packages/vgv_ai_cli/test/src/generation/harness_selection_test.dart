import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/generation/harness_selection.dart';

void main() {
  group('HarnessSelection', () {
    test('is empty when nothing is selected', () {
      expect(const HarnessSelection().isEmpty, isTrue);
    });

    test('is not empty when any harness is selected', () {
      expect(const HarnessSelection(pi: true).isEmpty, isFalse);
    });

    test('toVars maps each flag onto its brick var', () {
      expect(const HarnessSelection(claude: true, opencode: true).toVars(), {
        'claude': true,
        'gemini': false,
        'codex': false,
        'opencode': true,
        'pi': false,
      });
    });

    test('all enables every harness', () {
      expect(HarnessSelection.all.toVars().values, everyElement(isTrue));
    });
  });
}
