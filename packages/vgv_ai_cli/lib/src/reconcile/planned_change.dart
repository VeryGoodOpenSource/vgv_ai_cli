import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';

/// How a [PlannedChange] reaches the file it targets.
enum ChangeMode { own, mergeJson, mergeToml }

/// {@template planned_change}
/// One file `vgv_ai install` intends to write.
///
/// Changes are planned before anything is applied, so `--check` can print them
/// and the merge rules live in one place rather than in each harness.
///
/// [file] is a `package:file` [File] rather than a `dart:io` one so a plan can
/// be built and applied against an in-memory filesystem, and so it matches the
/// `plugin_source` model the plan is derived from.
/// {@endtemplate}
class PlannedChange {
  /// The file belongs to us. Write it wholesale.
  new own({required this.file, required this.contents, this.harness})
    : mode = ChangeMode.own;

  /// Deep merge a JSON document into whatever is already there.
  new mergeJson({required this.file, required this.contents, this.harness})
    : mode = ChangeMode.mergeJson;

  /// Deep merge a TOML document into whatever is already there.
  new mergeToml({required this.file, required this.contents, this.harness})
    : mode = ChangeMode.mergeToml;

  /// The file to write.
  final File file;

  /// The content to write or merge, depending on [mode].
  final String contents;

  /// How [contents] reaches [file].
  final ChangeMode mode;

  /// The harness this change configures, or `null` when it is shared.
  ///
  /// `~/.agents/skills` is read by four harnesses from one copy, so the
  /// changes that write it belong to no single harness. Nullable rather than
  /// a `shared` enum entry, because [Harness] is the set of harnesses
  /// `vgv_ai` configures and a shared directory is not one of them.
  ///
  /// `uninstall` and `doctor` read this to answer what VGV wrote and for whom.
  final Harness? harness;

  @override
  String toString() {
    final owner = harness?.name ?? 'shared';
    return '[${mode.name}] ($owner) ${file.path}';
  }
}

/// What actually happened to a file.
enum ChangeOutcome { created, updated, skipped, unchanged }

/// {@template applied_change}
/// The result of applying a [PlannedChange].
/// {@endtemplate}
class AppliedChange {
  /// The file did not exist and was created.
  new created({required this.change}) : outcome = ChangeOutcome.created;

  /// The file existed and its content changed.
  new updated({required this.change}) : outcome = ChangeOutcome.updated;

  /// The change was declined because the user's value won a conflict.
  new skipped({required this.change}) : outcome = ChangeOutcome.skipped;

  /// The file already had the intended content.
  new unchanged({required this.change}) : outcome = ChangeOutcome.unchanged;

  /// The change that was applied.
  final PlannedChange change;

  /// What happened.
  final ChangeOutcome outcome;
}
