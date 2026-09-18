import 'package:hooks/models/mcp_server.dart';
import 'package:json_annotation/json_annotation.dart';

part 'mcp_server_config.g.dart';

/// {@template mcp_server_config}
/// The shape Gemini CLI and Codex both use to describe an MCP server.
///
/// Every field is nullable so empty command, args, env or url are dropped from
/// the output rather than emitted as empty values.
/// {@endtemplate}
@JsonSerializable(createFactory: false, includeIfNull: false)
class const MCPServerConfig({
  final String? command,
  final List<String>? args,
  final Map<String, dynamic>? env,
  final String? url,
}) {
  /// Builds the config that describes [server], dropping empty values.
  factory fromMCPServer(MCPServer server) => MCPServerConfig(
    command: server.isRemote ? null : server.command,
    args: server.args.isEmpty ? null : server.args,
    env: server.env.isEmpty ? null : server.env,
    url: server.url,
  );

  /// Serializes the server config to JSON.
  Map<String, dynamic> toJson() => _$MCPServerConfigToJson(this);
}
