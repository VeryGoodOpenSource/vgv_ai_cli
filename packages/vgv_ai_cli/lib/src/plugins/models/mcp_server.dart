/// {@template mcp_server}
/// A Model Context Protocol server resolved from a VGV plugin's `.mcp.json`.
///
/// A server is either remote (it carries a [url]) or local (it is launched
/// through a [command] with [args] and an optional [env]). The `agents` brick
/// re-parses the [toVars] shape and lets each harness spell the server in its
/// own dialect.
/// {@endtemplate}
class const McpServer({
  final String? command,
  final List<String> args = const [],
  final Map<String, dynamic> env = const {},
  final String? url,
}) {
  /// Parses an [McpServer] from a single `.mcp.json` server entry.
  ///
  /// Values are coerced rather than cast because plugin JSON is authored by
  /// hand and cannot be trusted to match the expected types exactly.
  factory fromJson(Map<dynamic, dynamic> json) {
    final rawArgs = json['args'];
    final rawEnv = json['env'];
    final url = json['url'];
    return McpServer(
      command: json['command'] is String ? json['command'] as String : null,
      args: <String>[
        if (rawArgs is List)
          for (final arg in rawArgs) '$arg',
      ],
      env: <String, dynamic>{
        if (rawEnv is Map)
          for (final MapEntry(:key, :value) in rawEnv.entries) '$key': value,
      },
      url: url is String ? url : null,
    );
  }

  /// Whether the server is reached over the network rather than launched
  /// locally.
  bool get isRemote => url != null;

  /// The mason var shape the `agents` brick reads for a single server.
  Map<String, dynamic> toVars() => <String, dynamic>{
    if (command != null) 'command': command,
    if (args.isNotEmpty) 'args': args,
    if (env.isNotEmpty) 'env': env,
    if (url != null) 'url': url,
  };
}
