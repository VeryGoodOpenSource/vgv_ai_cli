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

    test('installs every detected harness when it names none', () {
      expect(const FixCommand(harnesses: {}).toString(), 'vgv_ai install');
    });
  });
}
