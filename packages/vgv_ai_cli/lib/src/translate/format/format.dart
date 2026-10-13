/// The shared pieces every translator renders with.
///
/// Sits below the translators: they may all import this, and none imports
/// another translator.
library;

export 'agent_instructions.dart';
export 'codex_preamble.dart';
export 'vgv_paths.dart';
