import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group(FixCommand, () {
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

    test('names each plugin with --plugin, in pinned order', () {
      expect(
        FixCommand(
          harnesses: const {Harness.codex},
          plugins: {for (final plugin in vgvPlugins) plugin.name},
        ).toString(),
        [
          'vgv_ai install --only codex',
          for (final plugin in vgvPlugins) '--plugin ${plugin.name}',
        ].join(' '),
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

      test('keeps the plugins every fix installs', () {
        expect(
          FixCommand.combine([
            FixCommand(
              harnesses: const {Harness.codex},
              plugins: {vgvPlugins.first.name},
            ),
            FixCommand(
              harnesses: const {Harness.pi},
              plugins: {vgvPlugins.first.name},
            ),
          ]).toString(),
          'vgv_ai install --only codex --only pi '
          '--plugin ${vgvPlugins.first.name}',
        );
      });

      test('is null when the fixes install different plugins', () {
        expect(
          FixCommand.combine([
            FixCommand(
              harnesses: const {Harness.codex},
              plugins: {vgvPlugins.first.name},
            ),
            const FixCommand(harnesses: {Harness.pi}),
          ]),
          isNull,
        );
      });

      test('is null when there is nothing to fix', () {
        expect(FixCommand.combine(const []), isNull);
        expect(FixCommand.combine(const [null, null]), isNull);
      });
    });
  });
}
