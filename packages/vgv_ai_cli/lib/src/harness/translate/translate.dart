/// Turns the harness-neutral plugin assets into each harness's own files.
///
/// One `HarnessTranslator` per harness, plus the `SkillsTranslator` that
/// writes the single shared copy of the skills. Translators depend on the
/// neutral model and on the reconcile layer; none depends on another
/// translator.
library;

export 'claude_translator.dart';
export 'format/mcp_tool_map.dart';
export 'harness_translator.dart';
export 'skills_translator.dart';
export 'staged_output.dart';
export 'translation_result.dart';
