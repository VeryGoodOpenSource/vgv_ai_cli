import 'package:hooks/models/mcp_server.dart';
import 'package:json_annotation/json_annotation.dart';

part 'opencode_mcp_server.g.dart';

/// {@template opencode_mcp_server}
/// The shape OpenCode uses to describe an MCP server.
///
/// OpenCode types every server and merges the command and its args into a
/// single array under [command].
/// {@endtemplate}
@JsonSerializable(createFactory: false, includeIfNull: false)
class const OpenCodeMcpServer({
  required final String type,
  final List<String>? command,
  final String? url,
  final Map<String, dynamic>? environment,
}) {
  /// Builds the config that describes [server].
  factory fromMcpServer(McpServer server) => server.isRemote
      ? OpenCodeMcpServer(type: 'remote', url: server.url)
      : OpenCodeMcpServer(
          type: 'local',
          command: <String>[server.command ?? '', ...server.args],
          environment: server.env.isEmpty ? null : server.env,
        );

  /// Serializes the server config to JSON.
  Map<String, dynamic> toJson() => _$OpenCodeMcpServerToJson(this);
}
