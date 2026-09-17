import 'package:hooks/models/mcp_server.dart';
import 'package:hooks/models/mcp_server_config/mcp_server_config.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gemini_settings.g.dart';

/// {@template gemini_context}
/// Tells Gemini CLI which file holds the shared agent instructions.
/// {@endtemplate}
@JsonSerializable(createFactory: false)
class const GeminiContext({final String fileName = 'AGENTS.md'}) {
  /// Serializes the context to JSON.
  Map<String, dynamic> toJson() => _$GeminiContextToJson(this);
}

/// {@template gemini_settings}
/// The settings fragment merged into `~/.gemini/settings.json`.
/// {@endtemplate}
@JsonSerializable(createFactory: false, explicitToJson: true)
class const GeminiSettings({
  required final Map<String, MCPServerConfig> mcpServers,
  final GeminiContext context = const GeminiContext(),
}) {
  /// Builds the settings from the resolved [servers].
  factory fromServers(Map<String, MCPServer> servers) => GeminiSettings(
    mcpServers: {
      for (final MapEntry(:key, :value) in servers.entries)
        key: MCPServerConfig.fromMCPServer(value),
    },
  );

  /// Serializes the settings fragment to JSON.
  Map<String, dynamic> toJson() => _$GeminiSettingsToJson(this);
}
