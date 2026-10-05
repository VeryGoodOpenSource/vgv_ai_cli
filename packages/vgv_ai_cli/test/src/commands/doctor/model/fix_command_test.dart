import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('FixCommand', () {
    test('names each harness with --only, in harness order', () {
      expect(
        const FixCommand(harnesses: {Harness.gemini, Harness.codex}).toString(),
        'vgv_ai install --only gemini --only codex',
      );
    });

    test('ends with --force when forced', () {
      expect(
        const FixCommand(harnesses: {Harness.codex}, force: true).toString(),
        'vgv_ai install --only codex --force',
      );
    });

    group('combine', () {
      test('installs every harness any fix names', () {
        expect(
          FixCommand.combine(const [
            FixCommand(harnesses: {Harness.codex}),
            null,
            FixCommand(harnesses: {Harness.gemini, Harness.codex}),
          ]).toString(),
          'vgv_ai install --only gemini --only codex',
        );
      });

      test('forces when any fix forces', () {
        expect(
          FixCommand.combine(const [
            FixCommand(harnesses: {Harness.codex}),
            FixCommand(harnesses: {Harness.pi}, force: true),
          ]).toString(),
          'vgv_ai install --only codex --only pi --force',
        );
      });

      test('is null when there is nothing to fix', () {
        expect(FixCommand.combine(const []), isNull);
        expect(FixCommand.combine(const [null, null]), isNull);
      });
    });

    test('installs every detected harness when it names none', () {
      expect(const FixCommand(harnesses: {}).toString(), 'vgv_ai install');
    });
  });
}
