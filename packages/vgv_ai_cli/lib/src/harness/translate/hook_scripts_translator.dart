import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template hook_scripts_translator}
/// Copies each plugin's `hooks/` tree to a directory VGV owns.
///
/// Planned once rather than per harness, like the shared skills: three
/// harnesses reference the same scripts, so the copies belong to none of them.
/// Not a `HarnessTranslator` for exactly that reason.
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

      // followLinks is off so a link is reported rather than followed, which
      // matches how the shared skills are copied.
      for (final entity in source.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Directory) continue;

        final relative = p.relative(entity.path, from: source.path);
        if (entity is! File) {
          notes.add(
            TranslationNote(
              subject: '$plugin hooks/$relative',
              reason:
                  'it is a symlink, which is not copied, so any hook that '
                  'runs it will fail',
            ),
          );
          continue;
        }

        changes.add(
          PlannedChange.own(
            file: home.fileSystem.file(p.join(target.path, relative)),
            contents: entity.readAsStringSync(),
            harness: null,
          ),
        );
      }
    }

    return TranslationResult(changes: changes, notes: notes);
  }
}
