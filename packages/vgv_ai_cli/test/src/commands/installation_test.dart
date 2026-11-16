import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/commands.dart';

void main() {
  group(Installation, () {
    group('fromExecutable', () {
      test('is pub for the dart executable', () {
        expect(
          Installation.fromExecutable('/usr/lib/dart/bin/dart'),
          Installation.pub,
        );
      });

      test('is homebrew for an executable in the Cellar', () {
        expect(
          Installation.fromExecutable(
            '/opt/homebrew/Cellar/vgv_ai/1.0.0/bin/vgv_ai',
          ),
          Installation.homebrew,
        );
        expect(
          Installation.fromExecutable(
            '/home/linuxbrew/.linuxbrew/Cellar/vgv_ai/1.0.0/bin/vgv_ai',
          ),
          Installation.homebrew,
        );
      });

      test('is script for any other executable', () {
        expect(
          Installation.fromExecutable('/home/me/.local/bin/vgv_ai'),
          Installation.script,
        );
      });
    });

    test('current is pub under dart test', () {
      expect(Installation.current, Installation.pub);
    });

    test('names the command that upgrades each installation', () {
      expect(Installation.pub.upgradeCommand, 'vgv_ai update');
      expect(Installation.homebrew.upgradeCommand, 'brew upgrade vgv_ai');
      expect(Installation.script.upgradeCommand, installScriptCommand);
    });
  });
}
