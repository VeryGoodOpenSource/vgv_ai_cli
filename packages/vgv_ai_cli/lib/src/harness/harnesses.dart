import 'package:vgv_ai_cli/src/harness/claude_harness.dart';
import 'package:vgv_ai_cli/src/harness/codex_harness.dart';
import 'package:vgv_ai_cli/src/harness/gemini_harness.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/harness/opencode_harness.dart';
import 'package:vgv_ai_cli/src/harness/pi_harness.dart';

export 'package:vgv_ai_cli/src/harness/claude_harness.dart';
export 'package:vgv_ai_cli/src/harness/codex_harness.dart';
export 'package:vgv_ai_cli/src/harness/gemini_harness.dart';
export 'package:vgv_ai_cli/src/harness/harness.dart';
export 'package:vgv_ai_cli/src/harness/opencode_harness.dart';
export 'package:vgv_ai_cli/src/harness/pi_harness.dart';

/// Every harness `vgv_ai` can configure, in reporting order.
const allHarnesses = <Harness>[
  ClaudeHarness(),
  GeminiHarness(),
  CodexHarness(),
  OpenCodeHarness(),
  PiHarness(),
];
