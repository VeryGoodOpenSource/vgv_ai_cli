import 'package:hooks/models/mcp_server.dart';
import 'package:hooks/models/settings/mcp_server_config.dart';
import 'package:toml/toml.dart';

/// {@template codex_config}
/// The config fragment merged into `~/.codex/config.toml`.
///
/// Codex declares servers as `[mcp_servers.<name>]` tables. The `toml` package
/// owns serialization so the model never hand-formats tables or quoting; each
/// server is serialized to a map by its [McpServerConfig] first.
/// {@endtemplate}
class const CodexConfig(final Map<String, McpServerConfig> servers) {
  /// Builds the config from the resolved [servers].
  factory fromServers(Map<String, McpServer> servers) => CodexConfig({
    for (final MapEntry(:key, :value) in servers.entries)
      key: McpServerConfig.fromMcpServer(value),
  });

  /// Serializes the config fragment to TOML.
  String toToml() {
    if (servers.isEmpty) return '# No MCP servers were resolved.';
    final tables = {
      for (final MapEntry(:key, :value) in servers.entries) key: value.toJson(),
    };
    return TomlDocument.fromMap({'mcp_servers': tables}).toString().trimRight();
  }
}
