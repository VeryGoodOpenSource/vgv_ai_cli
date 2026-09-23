import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';

/// The canonical directory the translated skills are written to.
///
/// Gemini, Codex, OpenCode and Pi all read `~/.agents/skills` with no
/// configuration, so one copy serves four harnesses. Claude Code needs none: it
/// installs the same plugins from the marketplace, and a second copy would
/// drift from the first.
Directory agentsSkillsRoot(Directory home) =>
    home.fileSystem.directory(p.join(home.path, '.agents', 'skills'));

/// Where VGV keeps its copy of a plugin's files.
///
/// The hook scripts are copied here rather than referenced where the plugin
/// resolved to. A plugin cache is Claude Code's to clear, and a hook pointing
/// into a cleared cache fails on every tool call; a copy VGV owns is also one
/// `uninstall` can reverse.
Directory vgvPluginRoot(Directory home, String plugin) => home.fileSystem
    .directory(p.join(home.path, '.agents', 'vgv', 'plugins', plugin));

/// Resolves one hook command against the copied scripts.
///
/// Substitutes the neutral [HookCommand.pluginRoot] placeholder, then runs a
/// `.sh` path through `bash`. Every hook script both plugins ship starts
/// `#!/bin/bash`, so this is exactly equivalent to executing it directly and
/// avoids depending on a permission bit that a Dart file write cannot set.
String resolveHookCommand(
  HookCommand command, {
  required Directory home,
  required String plugin,
}) {
  final resolved = command.command.replaceAll(
    HookCommand.pluginRoot,
    vgvPluginRoot(home, plugin).path,
  );

  // Bare-ness is judged on the command as written, not on the resolved path.
  // A home directory containing a space is ordinary on macOS, so the resolved
  // path may have one even when the command was a single token; the quotes
  // are what make that safe.
  final bare =
      !command.command.contains(' ') && command.command.endsWith('.sh');
  return bare ? "bash '$resolved'" : resolved;
}
