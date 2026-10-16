/// Turns the harness-neutral plugin assets into each harness's own files.
///
/// The `agents` brick decides which files each harness gets. Each
/// `HarnessTranslator` spells the contents the brick cannot, and
/// `SkillsTranslator` writes the single shared copy of the skills. None
/// depends on another translator.
library;

export 'agents_brick.dart';
export 'agents_vars.dart';
export 'format/format.dart';
export 'harness_translator.dart';
export 'hook_scripts.dart';
export 'model/model.dart';
export 'rendered_change.dart';
export 'translator.dart';
export 'translators/translators.dart';
