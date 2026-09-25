/// The shared pieces every translator renders with.
///
/// Sits below the translators: they may all import this, and none imports
/// another translator.
library;

export 'agent_markdown.dart';
export 'hook_event_map.dart';
export 'mcp_tool_map.dart';
export 'vgv_paths.dart';
