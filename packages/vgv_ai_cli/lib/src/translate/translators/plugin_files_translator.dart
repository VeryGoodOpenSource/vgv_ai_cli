import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/copy_source.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template plugin_files_translator}
/// Copies the plugin files the skill and agent bodies read in place into a
/// project, so a clone of the project has them.
///
/// Only the top-level entries a body names through `${CLAUDE_PLUGIN_ROOT}`
/// are copied, under `ProjectScope.pluginRoot`, where the parser spelled
/// them. The rest of the plugin, such as its evals and repository files,
/// stays out of the project.
///
/// Not a `HarnessTranslator`, because the copy belongs to no single harness.
/// {@endtemplate}
class const PluginFilesTranslator() {
  /// {@macro plugin_files_translator}
  this;

  /// Plans every file under each of [plugins]' referenced entries, shared,
  /// in [scope].
  TranslationResult translate({
    required List<PluginDirectory> plugins,
    required ProjectScope scope,
  }) {
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];
    for (final plugin in plugins) {
      final target = scope.root.fileSystem.directory(
        scope.root.fileSystem.path.joinAll([
          scope.root.path,
          ...scope.pluginRoot(plugin.plugin).split('/'),
        ]),
      );
      for (final entry in plugin.referencedEntries) {
        changes.addAll(_entryFiles(plugin, entry, target, notes));
      }
    }
    return TranslationResult(changes: changes, notes: notes);
  }

  /// Plans every file under [entry] of [plugin] beneath [target], adding to
  /// [notes] what cannot be copied.
  List<PlannedChange> _entryFiles(
    PluginDirectory plugin,
    String entry,
    Directory target,
    List<TranslationNote> notes,
  ) {
    final fs = plugin.directory.fileSystem;
    final path = fs.path.join(plugin.directory.path, entry);
    final subject = '${plugin.plugin.name}/$entry';

    final type = fs.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      notes.add(
        TranslationNote(
          subject: subject,
          reason: 'the skills and agents name it, but the plugin has none',
        ),
      );
      return const [];
    }

    // followLinks is off so a symlinked directory is reported rather than
    // walked, which a cycle would otherwise turn into a hang.
    final entities = switch (type) {
      FileSystemEntityType.directory =>
        fs.directory(path).listSync(recursive: true, followLinks: false),
      FileSystemEntityType.link => [fs.link(path)],
      _ => [fs.file(path)],
    };

    final changes = <PlannedChange>[];
    for (final entity in entities) {
      if (entity is Directory) continue;

      final relative = fs.path.relative(
        entity.path,
        from: plugin.directory.path,
      );
      final source = entity.copySource(
        '${plugin.plugin.name}/${fs.path.split(relative).join('/')}',
        notes,
      );
      if (source == null) continue;

      changes.add(
        PlannedChange(
          file: target.fileSystem.file(
            target.fileSystem.path.join(target.path, relative),
          ),
          bytes: source.readAsBytesSync(),
          harness: null,
          source: source,
        ),
      );
    }
    return changes;
  }
}
