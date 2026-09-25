import 'package:plugin_source/plugin_source.dart';

/// How Gemini and Codex both spell an MCP server.
///
/// Empty `args` and `env` are left out rather than written empty.
Map<String, Object> mcpServerEntry(MCPServer server) => switch (server) {
  LocalMCPServer(:final command, :final args, :final env) => {
    'command': command,
    if (args.isNotEmpty) 'args': args,
    if (env.isNotEmpty) 'env': env,
  },
  RemoteMCPServer(:final url) => {'url': url},
};
