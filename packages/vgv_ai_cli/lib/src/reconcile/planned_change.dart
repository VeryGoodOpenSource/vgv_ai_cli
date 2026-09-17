import 'dart:io';

/// How a [PlannedChange] should be applied to the file it targets.
enum ChangeMode {
  /// The file belongs to us. Write it wholesale.
  ///
  /// Used for skills, agents, commands and prompts, which are generated from
  /// the plugins and carry nothing the user authored.
  own,

  /// Deep merge a JSON document into whatever is already there.
  ///
  /// Keys we do not know about survive, and on a conflict the existing value
  /// wins unless the change is forced.
  mergeJson,

  /// Merge TOML tables, with the same conflict rules as [mergeJson].
  mergeToml,

  /// Replace only the region between the VGV markers.
  ///
  /// Everything the user wrote outside the markers is preserved byte for byte.
  block,
}

/// {@template planned_change}
/// One file `vgv_ai install` intends to write.
///
/// Changes are planned before anything is applied so `--check` can print them
/// and the merge and backup rules can live in one place rather than in each
/// harness.
/// {@endtemplate}
class PlannedChange {
  /// {@macro planned_change}
  const new({
    required this.file,
    required this.contents,
    required this.mode,
    required this.harness,
  });

  /// The file to write.
  final File file;

  /// The content to write, merge or insert, depending on [mode].
  final String contents;

  /// How [contents] reaches [file].
  final ChangeMode mode;

  /// The harness this change belongs to, for reporting and for `uninstall`.
  final String harness;

  @override
  String toString() => '[${mode.name}] ${file.path}';
}

/// The result of applying a [PlannedChange].
enum ChangeOutcome {
  /// The file did not exist and was created.
  created,

  /// The file existed and its content changed.
  updated,

  /// The file already had the intended content.
  unchanged,

  /// The change was skipped because the user's value won a conflict.
  skipped,
}

/// {@template applied_change}
/// What actually happened to a file.
/// {@endtemplate}
class AppliedChange {
  /// {@macro applied_change}
  const new({required this.change, required this.outcome, this.backup});

  /// The change that was applied.
  final PlannedChange change;

  /// What happened.
  final ChangeOutcome outcome;

  /// The backup taken before the first modification, when one was needed.
  final File? backup;
}
