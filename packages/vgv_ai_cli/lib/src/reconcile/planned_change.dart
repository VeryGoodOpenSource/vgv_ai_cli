import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

enum ChangeMode { own, mergeJson, mergeToml, mergeMarkdown }

class PlannedChange {
  new own({required this.file, required this.contents, required this.harness})
    : mode = ChangeMode.own;

  new mergeJson({
    required this.file,
    required this.contents,
    required this.harness,
  }) : mode = ChangeMode.mergeJson;

  new mergeToml({
    required this.file,
    required this.contents,
    required this.harness,
  }) : mode = ChangeMode.mergeToml;

  new mergeMarkdown({
    required this.file,
    required this.contents,
    required this.harness,
  }) : mode = ChangeMode.mergeMarkdown;

  final File file;

  final String contents;

  final ChangeMode mode;

  /// Null when the change is shared rather than owned by one harness.
  final Harness? harness;

  @override
  String toString() {
    final owner = harness?.name ?? 'shared';
    return '[${mode.name}] ($owner) ${file.path}';
  }
}

enum ChangeOutcome { created, updated, skipped, unchanged }

class AppliedChange {
  new created({required this.change}) : outcome = ChangeOutcome.created;

  new updated({required this.change}) : outcome = ChangeOutcome.updated;

  new skipped({required this.change}) : outcome = ChangeOutcome.skipped;

  new unchanged({required this.change}) : outcome = ChangeOutcome.unchanged;

  final PlannedChange change;

  final ChangeOutcome outcome;
}
