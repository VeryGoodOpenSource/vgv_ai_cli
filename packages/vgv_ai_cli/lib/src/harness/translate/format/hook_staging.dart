import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Where VGV keeps its copy of a plugin's files.
///
/// The hook scripts are copied here rather than referenced where the plugin
/// resolved to. A plugin cache is Claude Code's to clear, and a hook pointing
/// into a cleared cache fails on every tool call; a copy VGV owns is also one
/// `uninstall` can reverse.
Directory vgvPluginRoot(Directory home, String plugin) => home.fileSystem
    .directory(p.join(home.path, '.agents', 'vgv', 'plugins', plugin));

/// {@template hook_scripts_translator}
/// Copies each plugin's `hooks/` tree to a directory VGV owns.
///
/// Planned once rather than per harness, like the shared skills: three
/// harnesses reference the same scripts, so the copies belong to none of them.
/// {@endtemplate}
class const HookScriptsTranslator() {
  /// Plans a copy of every hook script the resolved plugins ship.
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
  }) {
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    // Several hooks share one plugin's directory, so copy each tree once.
    final trees = <String, Directory>{};
    for (final hook in assets.hooks) {
      trees[hook.plugin] = hook.directory;
    }

    for (final MapEntry(key: plugin, value: source) in trees.entries) {
      if (!source.existsSync()) {
        notes.add(
          TranslationNote(
            subject: '$plugin hooks',
            reason:
                '${source.path} has gone away, so its scripts were not '
                'copied and its hooks will not run',
          ),
        );
        continue;
      }

      final target = vgvPluginRoot(
        home,
        plugin,
      ).childDirectory(p.basename(source.path));
      for (final entity in source.listSync(recursive: true)) {
        if (entity is! File) continue;
        changes.add(
          PlannedChange.own(
            file: home.fileSystem.file(
              p.join(target.path, p.relative(entity.path, from: source.path)),
            ),
            contents: entity.readAsStringSync(),
          ),
        );
      }
    }

    return TranslationResult(changes: changes, notes: notes);
  }
}

/// Resolves one hook command against the copied scripts.
///
/// Substitutes the neutral [HookCommand.pluginRoot] placeholder, then runs a
/// bare `.sh` path through `bash`. Every hook script both plugins ship starts
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

  final bare = !resolved.contains(' ') && resolved.endsWith('.sh');
  return bare ? 'bash $resolved' : resolved;
}
