import 'package:hooks/models/mcp_server.dart';
import 'package:json_annotation/json_annotation.dart';

part 'opencode_mcp_server.g.dart';

/// How OpenCode reaches an MCP server.
enum OpenCodeMCPServerType {
  /// The server is launched locally through a command.
  @JsonValue('local')
  local,

  /// The server is reached over the network through a url.
  @JsonValue('remote')
  remote,
}

/// {@template opencode_mcp_server}
/// The shape OpenCode uses to describe an MCP server.
///
/// OpenCode types every server and merges the command and its args into a
/// single array under [command].
/// {@endtemplate}
@JsonSerializable(createFactory: false, includeIfNull: false)
class const OpenCodeMCPServer({
  required final OpenCodeMCPServerType type,
  final List<String>? command,
  final String? url,
  final Map<String, dynamic>? environment,
}) {
  /// Builds the config that describes [server].
  factory fromMCPServer(MCPServer server) => server.isRemote
      ? OpenCodeMCPServer(
          type: OpenCodeMCPServerType.remote,
          url: server.url,
        )
      : OpenCodeMCPServer(
          type: OpenCodeMCPServerType.local,
          command: <String>[server.command ?? '', ...server.args],
          environment: server.env.isEmpty ? null : server.env,
        );

  /// Serializes the server config to JSON.
  Map<String, dynamic> toJson() => _$OpenCodeMCPServerToJson(this);
}
