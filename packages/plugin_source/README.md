# plugin_source

`plugin_source` resolves the pinned VGV Claude Code plugins to a directory on
disk and parses them into a harness-neutral asset model. `vgv_ai_cli` depends
on it to get the skills, agents, MCP servers, and hooks it translates for each
harness. The package isn't published.

## Usage

To read a plugin, resolve it to a directory with a `PluginSource`, then parse
that directory with a `PluginParser`. This example tries the Claude Code
plugin cache first and falls back to cloning each pinned plugin with git:

```dart
import 'dart:io';

import 'package:file/local.dart';
import 'package:plugin_source/plugin_source.dart';

Future<void> main() async {
  final home = const LocalFileSystem().directory(Platform.environment['HOME']);
  final sources = <PluginSource>[
    LocalCachePluginSource(home: home),
    GitPluginSource(
      cacheRoot: home.childDirectory('.vgv_ai').childDirectory('plugins'),
      runGit: (args) => Process.run('git', args),
    ),
  ];

  for (final plugin in vgvPlugins) {
    for (final source in sources) {
      final resolution = await source.resolve(plugin);
      if (resolution case ResolvedPlugin(:final directory)) {
        final assets = const ClaudePluginParser().parse(directory);
        print('$plugin: ${assets.skills.length} skills');
        break;
      }
    }
  }
}
```

A source that can't supply the plugin returns an `UnavailablePlugin` with the
reasons, rather than throwing. A plugin file that can't be understood makes
the parser throw a `PluginParseException` that names the file and the field.
`PluginAssets.merge` combines several plugins into one set of assets.

## Layout

The library has three layers under `lib/src/`, none of which knows about any
harness beyond its own parser:

- `format/`: the file formats every parser shares. `Frontmatter` parses and
  renders YAML frontmatter, and the `PluginSchema` extension validates decoded
  content against an [`ack`](https://pub.dev/packages/ack) schema, turning a
  mismatch into a `PluginParseException`.
- `model/`: the harness-neutral assets every parser produces and every
  translator consumes: `PluginAssets`, `SkillAsset`, `AgentAsset`,
  `MCPServer`, and `HookAsset`.
- `parser/`: one parser per input harness behind the `PluginParser`
  interface. `ClaudePluginParser` reads Claude Code plugins, and
  `claude_schemas.dart` holds the schema of each file it reads. A new input
  harness is one new implementation.

Beside them, `plugin_ref.dart` pins the plugins in `vgvPlugins`,
`sources.dart` holds the `PluginSource` implementations, and `resolution.dart`
holds the `PluginResolution` they return.

`tool/bump_plugin_pins.dart` moves each pin in `plugin_ref.dart` to its
plugin's latest GitHub release. A weekly workflow runs it and opens a pull
request.
