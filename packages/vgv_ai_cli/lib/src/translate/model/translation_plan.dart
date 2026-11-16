import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/translation_result.dart';

/// {@template translation_plan}
/// Everything translating the plugins for the selected harnesses produced.
/// {@endtemplate}
class const TranslationPlan({
  /// What no single harness owns: the shared copy of the skills, and in a
  /// project the plugin files they reference, or null when no selected
  /// harness reads either.
  final TranslationResult? shared,

  /// Each selected harness's own result, in reporting order.
  final Map<Harness, TranslationResult> harnesses = const {},
}) {
  /// {@macro translation_plan}
  this;

  /// Every planned change, the shared ones first.
  List<PlannedChange> get changes => [
    ...?shared?.changes,
    for (final result in harnesses.values) ...result.changes,
  ];
}
