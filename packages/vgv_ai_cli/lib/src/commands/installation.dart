import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/command_runner.dart';

/// The command that reinstalls `vgv_ai` through the install script.
const installScriptCommand =
    'curl -fsSL https://raw.githubusercontent.com/VeryGoodOpenSource/vgv_ai_cli/main/install.sh | bash';

/// {@template installation}
/// How `vgv_ai` was installed, which decides how it updates.
///
/// Only a [pub] installation updates itself. The others are told the
/// [upgradeCommand] to run, since a binary should not drive `brew` or rerun a
/// script on the user's behalf.
/// {@endtemplate}
enum Installation({
  /// What the user runs to upgrade this installation.
  required final String upgradeCommand,
}) {
  /// `dart pub global activate vgv_ai_cli`, which runs on the Dart VM.
  pub(upgradeCommand: '$executableName update'),

  /// The Homebrew formula, which installs into the Cellar.
  homebrew(upgradeCommand: 'brew upgrade vgv_ai'),

  /// The install script, or a release archive unpacked by hand.
  script(upgradeCommand: installScriptCommand);

  /// The installation the executable at [path] belongs to.
  ///
  /// A pub installation runs on the `dart` executable, and Homebrew resolves
  /// its links into a `Cellar` directory. Any other path is a prebuilt binary
  /// from a release archive.
  static Installation fromExecutable(String path) {
    if (p.basenameWithoutExtension(path) == 'dart') return pub;
    if (p.split(path).contains('Cellar')) return homebrew;
    return script;
  }

  /// The installation of the running executable.
  static Installation get current =>
      fromExecutable(Platform.resolvedExecutable);
}
