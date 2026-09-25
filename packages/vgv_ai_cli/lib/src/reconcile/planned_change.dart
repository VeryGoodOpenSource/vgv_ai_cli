import 'dart:io';

enum ChangeMode { own, mergeJson, mergeToml }

class PlannedChange {
  new own({required this.file, required this.contents}) : mode = ChangeMode.own;

  new mergeJson({required this.file, required this.contents})
    : mode = ChangeMode.mergeJson;

  new mergeToml({required this.file, required this.contents})
    : mode = ChangeMode.mergeToml;

  final File file;
  final String contents;
  final ChangeMode mode;

  @override
  String toString() => '[${mode.name}] ${file.path}';
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
