/// Harness-specific parsers that read plugin files into the neutral model.
///
/// Each input harness has one parser behind the `PluginParser` interface, so a
/// new harness is one new implementation. Output translators depend only on the
/// neutral model a parser returns, never on a parser itself.
library;

export 'claude_plugin_parser.dart';
export 'plugin_parser.dart';
