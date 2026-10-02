import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';

void main() {
  group('Finding', () {
    test('missing is fixed by install', () {
      const finding = Finding.missing('missing ~/a');

      expect(finding.kind, FindingKind.missing);
      expect(finding.message, 'missing ~/a');
      expect(finding.step, isNull);
      expect(finding.needsForce, isFalse);
    });

    test('drifted is fixed by install --force', () {
      const finding = Finding.drifted('changed ~/a');

      expect(finding.kind, FindingKind.drifted);
      expect(finding.step, isNull);
      expect(finding.needsForce, isTrue);
    });

    test('manual carries its own step', () {
      const finding = Finding.manual('cannot read ~/a', step: 'Fix it.');

      expect(finding.kind, FindingKind.manual);
      expect(finding.step, 'Fix it.');
      expect(finding.needsForce, isFalse);
    });

    test('warning and suggestion are not problems', () {
      const warning = Finding.warning('not installed');
      const suggestion = Finding.suggestion('not configured');

      expect(warning.kind, FindingKind.warning);
      expect(suggestion.kind, FindingKind.suggestion);
      expect(warning.isProblem, isFalse);
      expect(suggestion.isProblem, isFalse);
    });

    test('missing, drifted and manual are problems', () {
      expect(const Finding.missing('a').isProblem, isTrue);
      expect(const Finding.drifted('a').isProblem, isTrue);
      expect(const Finding.manual('a', step: 'b').isProblem, isTrue);
    });
  });
}
