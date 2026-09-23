import 'package:meta/meta.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template translation_note}
/// Something the source declared that a harness cannot express.
///
/// Carries no harness: `translate()` runs once per harness, so whoever holds
/// the notes already knows which translator produced them.
/// {@endtemplate}
@immutable
class const TranslationNote({
  /// What could not be translated, e.g. `PreToolUse hook (matcher: Bash)`.
  required final String subject,

  /// Why, e.g. `OpenCode has no pre-tool hook`.
  required final String reason,
}) {
  @override
  bool operator ==(Object other) =>
      other is TranslationNote &&
      other.subject == subject &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(subject, reason);

  @override
  String toString() => '$subject: $reason';
}

/// {@template translation_result}
/// What translating one harness produced.
///
/// [notes] is the reason this is a result rather than a bare list: a harness
/// that cannot express something reports it, so `install` can print it. Nothing
/// is dropped silently.
///
/// Deliberately no value equality: [PlannedChange] has none, so comparing two
/// results would compare changes by identity and read as a value comparison
/// that is not one. Tests assert on [changes] and [notes] directly.
/// {@endtemplate}
class const TranslationResult({
  /// The files this harness needs written.
  required final List<PlannedChange> changes,

  /// Everything this harness could not express.
  final List<TranslationNote> notes = const [],
});
