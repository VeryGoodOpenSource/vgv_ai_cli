/// The translators that spell each harness's own files, plus the one that
/// writes the shared copy of the skills.
///
/// A new harness gets its `<harness>_translator.dart` here, any
/// `<harness>_compat.dart` its hooks need beside it, an export below, and an
/// entry in `harnessTranslators`.
library;

export 'antigravity_compat.dart';
export 'antigravity_translator.dart';
export 'claude_translator.dart';
export 'codex_compat.dart';
export 'codex_translator.dart';
export 'copilot_compat.dart';
export 'copilot_translator.dart';
export 'gemini_translator.dart';
export 'harness_translators.dart';
export 'opencode_translator.dart';
export 'pi_translator.dart';
export 'skills_translator.dart';
