import 'package:args/command_runner.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

/// {@template harness_selection}
/// The `--only` and `--[no-]<harness>` options of a command that works on a
/// set of harnesses.
///
/// `--only` names the set outright. `--no-<harness>` narrows the default set
/// instead, so the two cannot be combined.
/// {@endtemplate}
mixin HarnessSelection on Command<int> {
  /// Adds the options, with [action] saying what the command does to each
  /// harness, such as `Configure the Very Good AI tooling for`, and [only]
  /// finishing the `--only` help.
  void addHarnessOptions(
    String action, {
    String only = 'just these harnesses, whether or not they are detected.',
  }) {
    argParser.addMultiOption(
      'only',
      help: '$action $only',
      allowed: Harness.values.map((harness) => harness.name),
    );

    // Opting out matters more than opting in: the default is every harness
    // that is actually installed, so `--no-<harness>` is how the set is
    // narrowed.
    for (final harness in Harness.values) {
      argParser.addFlag(
        harness.name,
        defaultsTo: true,
        help: '$action ${harness.displayName}.',
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
