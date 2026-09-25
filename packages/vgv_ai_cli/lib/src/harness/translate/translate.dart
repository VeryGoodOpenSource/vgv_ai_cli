/// Turns the harness-neutral plugin assets into each harness's own files.
///
/// One `HarnessTranslator` per harness, plus the `SkillsTranslator` that
/// writes the single shared copy of the skills. Translators depend on the
/// neutral model and on the reconcile layer; none depends on another
/// translator.
library;

import 'package:vgv_ai_cli/src/harness/translate/claude_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/codex_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/gemini_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/opencode_translator.dart';
import 'package:vgv_ai_cli/src/harness/translate/pi_translator.dart';

export 'claude_translator.dart';
export 'codex_translator.dart';
export 'gemini_translator.dart';
export 'harness_translator.dart';
export 'opencode_translator.dart';
export 'pi_translator.dart';
export 'skills_translator.dart';
export 'staged_output.dart';
export 'translation_result.dart';

/// Every harness translator, in reporting order.
///
/// Declared here rather than in a test, so the command wiring and the tests
/// read the same list and a new harness is registered exactly once.
const translators = <HarnessTranslator>[
  ClaudeTranslator(),
  GeminiTranslator(),
  CodexTranslator(),
  OpenCodeTranslator(),
  PiTranslator(),
];
