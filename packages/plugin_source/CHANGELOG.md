# 0.1.0

- feat: initial release.
- feat: resolve the pinned VGV plugins, `vgv-wingspan` and
  `vgv-ai-flutter-plugin`, to a directory on disk, from the Claude Code plugin
  cache or by cloning their pinned tag.
- feat: parse a Claude Code plugin's skills, agents, MCP servers and hooks
  into a harness-neutral asset model.
- feat: validate each plugin file against an `ack` schema, throwing a
  `PluginParseException` that names the file and the field.
- feat: `tool/bump_plugin_pins.dart` moves each pin to its plugin's latest
  GitHub release.
