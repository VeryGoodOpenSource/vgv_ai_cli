import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/command_runner.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';

/// The Homebrew formula the CLI is published as.
const homebrewFormula = 'verygoodopensource/tap/vgv_ai';

/// The script that installs the prebuilt CLI.
const installScriptUrl =
    'https://raw.githubusercontent.com/VeryGoodOpenSource/vgv_ai_cli/main/install.sh';

/// {@template install_method}
/// How `vgv_ai` itself was installed.
/// {@endtemplate}
enum InstallMethod {
  /// `dart pub global activate`, or a run from source, which `vgv_ai update`
  /// updates itself.
  pub,

  /// The Homebrew formula, which `brew upgrade` updates.
  homebrew,

  /// The prebuilt binary `install.sh` installed, which running the script
  /// again updates.
  script,
}

/// {@template cli_installation}
/// How `vgv_ai` was installed, and the command that updates it.
/// {@endtemplate}
class const CliInstallation._({
  /// How `vgv_ai` was installed.
  required final InstallMethod method,

  /// The command that updates `vgv_ai`, as it was installed.
  required final String upgradeCommand,
}) {
  /// {@macro cli_installation}
  ///
  /// Installed from pub.dev, so `vgv_ai update` updates it.
  const new pub()
    : this._(
        method: InstallMethod.pub,
        upgradeCommand: '$executableName update',
      );

  /// {@macro cli_installation}
  ///
  /// Installed by Homebrew, so `brew upgrade` updates it.
  const new homebrew()
    : this._(
        method: InstallMethod.homebrew,
        upgradeCommand: 'brew upgrade $homebrewFormula',
      );

  /// {@macro cli_installation}
  ///
  /// Installed by `install.sh`, so running it again updates it. The command
  /// names [installDirectory] when the binary is not in the script's default
  /// directory, so the update replaces this binary rather than adding one.
  factory script({String? installDirectory}) => CliInstallation._(
    method: InstallMethod.script,
    upgradeCommand: installDirectory == null
        ? 'curl -fsSL $installScriptUrl | bash'
        : 'curl -fsSL $installScriptUrl | '
              'VGV_AI_INSTALL_DIR=${_shellQuoted(installDirectory)} bash',
  );

  /// {@macro cli_installation}
  ///
  /// Tells how the running [executable], which should be
  /// `Platform.resolvedExecutable`, was installed. A compiled `vgv_ai` lives
  /// in Homebrew's Cellar when Homebrew installed it, and anywhere else when
  /// `install.sh` did. Any other executable, such as `dart`, runs the CLI
  /// from pub.dev or from source.
  factory detect(
    String executable, {
    required Map<String, String> environment,
  }) {
    if (p.basenameWithoutExtension(executable) != executableName) {
      return const CliInstallation.pub();
    }
    if (p.split(executable).contains('Cellar')) {
      return const CliInstallation.homebrew();
    }
    final directory = p.dirname(executable);
    final home = userHome(environment)?.path;
    final isDefault =
        home != null && p.equals(directory, p.join(home, '.local', 'bin'));
    return CliInstallation.script(
      installDirectory: isDefault ? null : directory,
    );
  }

  static String _shellQuoted(String value) =>
      RegExp(r'^[\w@%+=:,./-]+$').hasMatch(value)
      ? value
      : "'${value.replaceAll("'", r"'\''")}'";
}
