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

    test('missing, drifted, stale and manual are problems', () {
      expect(const Finding.missing('a').isProblem, isTrue);
      expect(const Finding.drifted('a').isProblem, isTrue);
      expect(const Finding.stale('a').isProblem, isTrue);
      expect(const Finding.manual('a', step: 'b').isProblem, isTrue);
    });

    test('stale is fixed by install, without --force', () {
      const finding = Finding.stale('a 1.0.0 installed, 2.0.0 pinned');

      expect(finding.kind, FindingKind.stale);
      expect(finding.needsForce, isFalse);
      expect(finding.isNotice, isFalse);
    });

    test('only warnings and suggestions are notices', () {
      expect(const Finding.warning('a').isNotice, isTrue);
      expect(const Finding.suggestion('a').isNotice, isTrue);
      expect(const Finding.current('a').isNotice, isFalse);
      expect(const Finding.missing('a').isNotice, isFalse);
    });

    test('needs install unless it is manual, a warning or current', () {
      expect(const Finding.missing('a').needsInstall, isTrue);
      expect(const Finding.drifted('a').needsInstall, isTrue);
      expect(const Finding.stale('a').needsInstall, isTrue);
      expect(const Finding.suggestion('a').needsInstall, isTrue);
      expect(const Finding.manual('a', step: 'b').needsInstall, isFalse);
      expect(const Finding.warning('a').needsInstall, isFalse);
      expect(const Finding.current('a').needsInstall, isFalse);
    });

    test('current is neither a problem nor a notice', () {
      const finding = Finding.current('a 1.0.0');

      expect(finding.kind, FindingKind.current);
      expect(finding.isProblem, isFalse);
    });
  });
}
