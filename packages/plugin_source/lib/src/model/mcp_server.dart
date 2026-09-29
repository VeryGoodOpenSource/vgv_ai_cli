/// {@template mcp_server}
/// A Model Context Protocol server a plugin declares, in a harness-neutral
/// shape.
///
/// The transport is a closed set: a server is either a [RemoteMCPServer]
/// (reached over a URL) or a [LocalMCPServer] (launched as a subprocess over
/// stdio). MCP defines no third transport, so the union has no unknown
/// fallback — a declaration that is neither is dropped at parse time rather
/// than modeled.
/// {@endtemplate}
sealed class MCPServer {
  /// {@macro mcp_server}
  const new({required this.name});

  /// The name the plugin declares the server under, unique across plugins.
  final String name;

  /// The server as a `.mcp.json` file declares it under its [name], leaving
  /// out every empty list and map rather than writing it empty.
  Map<String, Object> toJson();
}

/// {@template local_mcp_server}
/// A local MCP server launched as a subprocess and spoken to over stdio.
/// {@endtemplate}
final class LocalMCPServer extends MCPServer {
  /// {@macro local_mcp_server}
  const new({
    required super.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  /// The executable to launch.
  final String command;

  /// Arguments passed to [command].
  final List<String> args;

  /// Environment variables set for the subprocess.
  final Map<String, String> env;

  @override
  Map<String, Object> toJson() => {
    'command': command,
    if (args.isNotEmpty) 'args': args,
    if (env.isNotEmpty) 'env': env,
  };
}

/// {@template remote_mcp_server}
/// A remote MCP server reached over a URL.
/// {@endtemplate}
final class RemoteMCPServer extends MCPServer {
  /// {@macro remote_mcp_server}
  const new({required super.name, required this.url, this.headers = const {}});

  /// The endpoint the server is reached at.
  final String url;

  /// Headers sent with each request.
  final Map<String, String> headers;

  @override
  Map<String, Object> toJson() => {
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
  };
}
