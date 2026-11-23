import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/translation_note.dart';

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

  /// Each file an earlier version wrote, mapped to the file in [changes]
  /// that replaces it, both absolute.
  final Map<String, String> superseded = const {},
}) {
  /// {@macro translation_result}
  this;
}
