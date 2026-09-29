import 'package:equatable/equatable.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template translation_note}
/// Something the source declared that a harness cannot express.
///
/// Carries no harness: `translate()` runs once per harness, so whoever holds
/// the notes already knows which translator produced them.
/// {@endtemplate}
class const TranslationNote({
  /// What could not be translated.
  required final String subject,

  /// Why.
  required final String reason,
}) extends Equatable {
  @override
  List<Object?> get props => [subject, reason];

  @override
  String toString() => '$subject: $reason';
}

/// {@template translation_result}
/// What translating one harness produced.
///
/// [notes] is why this is a result rather than a bare list: a harness that
/// cannot express something reports it, so `install` can print it.
/// {@endtemplate}
class const TranslationResult({
  /// The files this harness needs written.
  required final List<PlannedChange> changes,

  /// Everything this harness could not express.
  final List<TranslationNote> notes = const [],
});
