/// {@template mcp_server}
/// A Model Context Protocol server a plugin declares, in a harness-neutral
/// shape.
///
/// The transport is a closed set: a server is either a [RemoteMcpServer]
/// (reached over a URL) or a [LocalMcpServer] (launched as a subprocess over
/// stdio). MCP defines no third transport, so the union has no unknown
/// fallback — a declaration that is neither is dropped at parse time rather
/// than modeled.
/// {@endtemplate}
sealed class McpServer {
  /// {@macro mcp_server}
  const new();
}

/// {@template local_mcp_server}
/// A local MCP server launched as a subprocess and spoken to over stdio.
/// {@endtemplate}
final class LocalMcpServer extends McpServer {
  /// {@macro local_mcp_server}
  const new({required this.command, this.args = const [], this.env = const {}});

  /// The executable to launch.
  final String command;

  /// Arguments passed to [command].
  final List<String> args;

  /// Environment variables set for the subprocess.
  final Map<String, String> env;
}

/// {@template remote_mcp_server}
/// A remote MCP server reached over a URL.
/// {@endtemplate}
final class RemoteMcpServer extends McpServer {
  /// {@macro remote_mcp_server}
  const new({required this.url, this.headers = const {}});

  /// The endpoint the server is reached at.
  final String url;

  /// Headers sent with each request.
  final Map<String, String> headers;
}
