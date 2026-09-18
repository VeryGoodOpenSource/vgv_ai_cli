/// {@template mcp_server}
/// A Model Context Protocol server the harnesses can talk to.
///
/// A server is either remote (it carries a [url]) or local (it is launched
/// through a [command] with [args] and an optional [env]). Each harness spells
/// the same server differently; the harness specific config objects know how
/// to build themselves from this domain model.
/// {@endtemplate}
class const MCPServer({
  final String? command,
  final List<String> args = const [],
  final Map<String, dynamic> env = const {},
  final String? url,
}) {
  /// Deserializes an [MCPServer] from the raw map supplied in `HookContext`.
  ///
  /// Mason vars arrive as loosely typed maps and lists, so the fields are
  /// coerced rather than cast.
  factory fromVars(Map<dynamic, dynamic> vars) {
    final url = vars['url'];
    final rawEnv = vars['env'];
    return MCPServer(
      command: vars['command'] as String?,
      args: (vars['args'] as List? ?? const []).cast<String>(),
      env: <String, dynamic>{
        if (rawEnv is Map)
          for (final MapEntry(:key, :value) in rawEnv.entries) '$key': value,
      },
      url: url is String ? url : null,
    );
  }

  /// Deserializes the map of servers keyed by name supplied in `HookContext`.
  ///
  /// Non-map values are dropped and each entry is coerced before parsing.
  static Map<String, MCPServer> mapFromVars(Object? rawServers) {
    if (rawServers is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in rawServers.entries)
        if (value is Map) '$key': MCPServer.fromVars(value),
    };
  }

  /// Whether the server is reached over the network rather than launched
  /// locally.
  bool get isRemote => url != null;
}
