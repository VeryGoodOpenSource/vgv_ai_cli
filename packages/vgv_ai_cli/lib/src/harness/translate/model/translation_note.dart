import 'package:equatable/equatable.dart';

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
