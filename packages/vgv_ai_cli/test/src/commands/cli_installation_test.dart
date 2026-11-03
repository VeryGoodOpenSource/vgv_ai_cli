import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/cli_installation.dart';

void main() {
  group(CliInstallation, () {
    const home = {'HOME': '/Users/dev'};

    group('detect', () {
      test('is pub when dart runs the CLI', () {
        final installation = CliInstallation.detect(
          '/opt/dart-sdk/bin/dart',
          environment: home,
        );

        expect(installation.method, InstallMethod.pub);
        expect(installation.upgradeCommand, 'vgv_ai update');
      });

      test('is homebrew when the binary lives in the Cellar', () {
        final installation = CliInstallation.detect(
          '/opt/homebrew/Cellar/vgv_ai/0.2.0/bin/vgv_ai',
          environment: home,
        );

        expect(installation.method, InstallMethod.homebrew);
        expect(
          installation.upgradeCommand,
          'brew upgrade verygoodopensource/tap/vgv_ai',
        );
      });

      test('is the script in its default directory', () {
        final installation = CliInstallation.detect(
          '/Users/dev/.local/bin/vgv_ai',
          environment: home,
        );

        expect(installation.method, InstallMethod.script);
        expect(
          installation.upgradeCommand,
          'curl -fsSL $installScriptUrl | bash',
        );
      });

      test('is the script in the directory it was installed to', () {
        final installation = CliInstallation.detect(
          '/usr/local/bin/vgv_ai',
          environment: home,
        );

        expect(installation.method, InstallMethod.script);
        expect(
          installation.upgradeCommand,
          'curl -fsSL $installScriptUrl | '
          'VGV_AI_INSTALL_DIR=/usr/local/bin bash',
        );
      });

      test('names the directory when there is no home', () {
        final installation = CliInstallation.detect(
          '/Users/dev/.local/bin/vgv_ai',
          environment: const {},
        );

        expect(
          installation.upgradeCommand,
          'curl -fsSL $installScriptUrl | '
          'VGV_AI_INSTALL_DIR=/Users/dev/.local/bin bash',
        );
      });
    });

    group('script', () {
      test('quotes a directory the shell would split', () {
        final installation = CliInstallation.script(
          installDirectory: "/Users/dev/my tools/it's",
        );

        expect(
          installation.upgradeCommand,
          'curl -fsSL $installScriptUrl | '
          r"VGV_AI_INSTALL_DIR='/Users/dev/my tools/it'\''s' bash",
        );
      });
    });
  });
}
