import 'package:plugin_source/plugin_source.dart';

/// How Gemini and Codex both spell an MCP server.
///
/// The two agree on everything but the key for a remote server's static
/// headers, which Gemini calls `headers` and Codex `http_headers`, so each
/// passes its own [headersKey]. Empty `args`, `env` and headers are left out
/// rather than written empty.
Map<String, Object> mcpServerEntry(
  MCPServer server, {
  required String headersKey,
}) => switch (server) {
  LocalMCPServer(:final command, :final args, :final env) => {
    'command': command,
    if (args.isNotEmpty) 'args': args,
    if (env.isNotEmpty) 'env': env,
  },
  RemoteMCPServer(:final url, :final headers) => {
    'url': url,
    if (headers.isNotEmpty) headersKey: headers,
  },
};
