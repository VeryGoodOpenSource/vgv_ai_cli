/// The shapes of the Claude Code plugin files, as far as the parser reads
/// them.
///
/// Each key the parser reads is typed, and a mismatch throws. Keys it does not
/// read pass through, so an upstream Claude addition is not a broken file.
library;

import 'package:ack/ack.dart';

/// `.claude-plugin/plugin.json`.
final ObjectSchema pluginManifestSchema = Ack.object({
  'name': Ack.string().optional(),
}).passthrough();

/// `.mcp.json`. A server with a `url` is remote, one with a `command` is
/// local.
final ObjectSchema mcpFileSchema = Ack.object({
  'mcpServers': Ack.map(
    Ack.object({
      'url': Ack.string().optional(),
      'headers': Ack.map(Ack.string()).optional(),
      'command': Ack.string().optional(),
      'args': Ack.list(Ack.string()).optional(),
      'env': Ack.map(Ack.string()).optional(),
    }).passthrough(),
  ).optional(),
}).passthrough();
