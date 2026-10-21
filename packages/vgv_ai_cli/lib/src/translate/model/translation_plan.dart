import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/translation_result.dart';

/// {@template translation_plan}
/// Everything translating the plugins for the selected harnesses produced.
/// {@endtemplate}
class const TranslationPlan({
  /// The shared copy of the skills, or null when no selected harness reads
  /// it.
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
