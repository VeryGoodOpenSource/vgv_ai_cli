import 'package:hooks/models/mcp_server.dart';
import 'package:hooks/models/opencode_mcp_server/opencode_mcp_server.dart';
import 'package:json_annotation/json_annotation.dart';

part 'opencode_config.g.dart';

/// {@template opencode_config}
/// The config fragment merged into `~/.config/opencode/opencode.json`.
/// {@endtemplate}
@JsonSerializable(createFactory: false, explicitToJson: true)
class const OpenCodeConfig({
  required final Map<String, OpenCodeMCPServer> mcp,
  @JsonKey(name: r'$schema')
  final String schema = 'https://opencode.ai/config.json',
  final List<String> instructions = const ['AGENTS.md'],
}) {
  /// Builds the config from the resolved [servers].
  factory fromServers(Map<String, MCPServer> servers) => OpenCodeConfig(
    mcp: {
      for (final MapEntry(:key, :value) in servers.entries)
        key: OpenCodeMCPServer.fromMCPServer(value),
    },
  );

  /// Serializes the config fragment to JSON.
  Map<String, dynamic> toJson() => _$OpenCodeConfigToJson(this);
}
