import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// The home directory [environment] names, or null when it names none.
Directory? userHome(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  return home == null ? null : const LocalFileSystem().directory(home);
}

/// {@template harness_selection}
/// The `--only` and `--[no-]<harness>` options of a command that works on a
/// set of harnesses.
///
/// `--only` names the set outright. `--no-<harness>` narrows the default set
/// instead, so the two cannot be combined.
/// {@endtemplate}
mixin HarnessSelection on Command<int> {
  /// Adds the options, with [verb] saying what the command does to each
  /// harness, such as `Configure`.
  void addHarnessOptions(String verb) {
    argParser.addMultiOption(
      'only',
      help: '$verb just these harnesses, whether or not they are detected.',
      allowed: Harness.values.map((harness) => harness.name),
    );

    // Opting out matters more than opting in: the default is every harness
    // that is actually installed, so `--no-<harness>` is how the set is
    // narrowed.
    for (final harness in Harness.values) {
      argParser.addFlag(
        harness.name,
        defaultsTo: true,
        help: '$verb ${harness.displayName}.',
      );
    }
  }

  /// The harnesses `--only` names, or null when it names none.
  ///
  /// Throws a [UsageException] when it is combined with a harness flag.
  Set<Harness>? get onlyHarnesses {
    final results = argResults!;
    final only = results['only'] as List<String>;
    if (only.isEmpty) return null;

    final flagged = Harness.values.where((h) => results.wasParsed(h.name));
    if (flagged.isNotEmpty) {
      usageException(
        '--only cannot be combined with '
        '${flagged.map((harness) => '--[no-]${harness.name}').join(', ')}.',
      );
    }
    return only.map(Harness.values.byName).toSet();
  }

  /// Whether `--no-<harness>` left [harness] in the default set.
  bool isEnabled(Harness harness) => argResults![harness.name] == true;
}
