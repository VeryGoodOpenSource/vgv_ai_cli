import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/antigravity_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/claude_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/codex_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/copilot_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/gemini_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/opencode_translator.dart';
import 'package:vgv_ai_cli/src/translate/translators/pi_translator.dart';

/// Every harness translator, in reporting order.
const harnessTranslators = <HarnessTranslator>[
  ClaudeTranslator(),
  GeminiTranslator(),
  CodexTranslator(),
  OpenCodeTranslator(),
  PiTranslator(),
  CopilotTranslator(),
  AntigravityTranslator(),
];
