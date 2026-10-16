import 'package:vgv_ai_cli/src/translate/translate.dart';

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
