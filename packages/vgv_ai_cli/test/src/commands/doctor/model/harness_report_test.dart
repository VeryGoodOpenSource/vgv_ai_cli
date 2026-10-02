import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('HarnessReport', () {
    test('is titled by its harness, or Shared', () {
      expect(
        const HarnessReport(
          owner: Harness.codex,
          installs: {Harness.codex},
          findings: [],
        ).title,
        'Codex',
      );
      expect(
        const HarnessReport(owner: null, installs: {}, findings: []).title,
        'Shared',
      );
    });

    test('has problems only when something wrong was found', () {
      expect(
        const HarnessReport(
          owner: null,
          installs: {},
          findings: [],
        ).hasProblems,
        isFalse,
      );
      expect(
        const HarnessReport(
          owner: null,
          installs: {},
          findings: [Finding.warning('a'), Finding.suggestion('b')],
        ).hasProblems,
        isFalse,
      );
      expect(
        const HarnessReport(
          owner: null,
          installs: {},
          findings: [Finding.missing('missing ~/a')],
        ).hasProblems,
        isTrue,
      );
    });

    test('fixes a finding by installing its harnesses', () {
      const report = HarnessReport(
        owner: null,
        installs: {Harness.codex, Harness.gemini},
        findings: [],
      );

      expect(
        report.fixFor(const Finding.missing('missing ~/a')).toString(),
        'vgv_ai install --only gemini --only codex',
      );
      expect(
        report.fixFor(const Finding.drifted('changed ~/a')).toString(),
        'vgv_ai install --only gemini --only codex --force',
      );
      expect(
        report.fixFor(const Finding.suggestion('a')).toString(),
        'vgv_ai install --only gemini --only codex',
      );
    });

    test('has no install fix for a manual step or a warning', () {
      const report = HarnessReport(
        owner: Harness.codex,
        installs: {Harness.codex},
        findings: [],
      );

      expect(report.fixFor(const Finding.manual('a', step: 'b')), isNull);
      expect(report.fixFor(const Finding.warning('a')), isNull);
    });
  });
}
