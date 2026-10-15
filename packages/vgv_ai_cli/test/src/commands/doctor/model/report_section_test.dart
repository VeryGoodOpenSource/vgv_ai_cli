import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group(ReportSection, () {
    test('has problems only when something wrong was found', () {
      expect(
        const ReportSection(
          title: 'Shared',
          installs: {},
          findings: [],
        ).hasProblems,
        isFalse,
      );
      expect(
        const ReportSection(
          title: 'Shared',
          installs: {},
          findings: [Finding.warning('a'), Finding.suggestion('b')],
        ).hasProblems,
        isFalse,
      );
      expect(
        const ReportSection(
          title: 'Shared',
          installs: {},
          findings: [Finding.missing('missing ~/a')],
        ).hasProblems,
        isTrue,
      );
    });

    test('has notices only when a warning or suggestion was found', () {
      expect(
        const ReportSection(
          title: 'Codex',
          installs: {},
          findings: [Finding.current('a'), Finding.missing('b')],
        ).hasNotices,
        isFalse,
      );
      expect(
        const ReportSection(
          title: 'Codex',
          installs: {},
          findings: [Finding.suggestion('a')],
        ).hasNotices,
        isTrue,
      );
    });

    ReportSection section(List<Finding> findings) => ReportSection(
      title: 'Shared',
      installs: const {Harness.codex, Harness.gemini},
      findings: findings,
    );

    test('fixes everything install can fix with one command', () {
      expect(
        section(const [
          Finding.missing('a'),
          Finding.stale('b'),
          Finding.suggestion('c'),
        ]).fix.toString(),
        'vgv_ai install --only gemini --only codex',
      );
    });

    test('forces the fix when anything drifted', () {
      expect(
        section(const [Finding.missing('a'), Finding.drifted('b')]).fix
            .toString(),
        'vgv_ai install --only gemini --only codex --force',
      );
    });

    test('has no fix when install changes nothing it found', () {
      expect(section(const []).fix, isNull);
      expect(
        section(const [
          Finding.manual('a', step: 'b'),
          Finding.warning('c'),
          Finding.current('d'),
        ]).fix,
        isNull,
      );
    });
  });
}
