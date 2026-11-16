import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/translation_note.dart';

/// {@template hook_translation}
/// What a harness makes of the plugins' hooks: the fragment merged into its
/// hooks file, the files that fragment points at, and what the user should
/// know about them.
/// {@endtemplate}
class const HookTranslation({
  /// The fragment merged into the harness's hooks file, or null when there
  /// is nothing to register.
  final String? fragment,

  /// The files [fragment] points at.
  final List<PlannedChange> files = const [],

  /// What could not be translated as intended, and what the user must do.
  final List<TranslationNote> notes = const [],
}) {
  /// {@macro hook_translation}
  this;
}
