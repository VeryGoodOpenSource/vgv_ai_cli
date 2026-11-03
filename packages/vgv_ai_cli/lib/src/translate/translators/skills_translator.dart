import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template skills_translator}
/// Writes a copy of the skills under one root: the shared one most harnesses
/// read, or a harness's own. The plugin files the skills and agents name
/// outside every skill go beside it, under [pluginFilesRoot].
///
/// Not a `HarnessTranslator`, because the shared copy belongs to no single
/// harness.
/// {@endtemplate}
class const SkillsTranslator() {
  /// {@macro skills_translator}
  this;

  /// Plans every skill under [root], plus the files each one ships alongside
  /// its `SKILL.md` and the plugin files [PluginAssets.paths] name, owned by
  /// [harness] or shared when null.
  TranslationResult translate({
    required PluginAssets assets,
    required Directory root,
    Harness? harness,
  }) {
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];
    final filesRoot = pluginFilesRoot(root);

    for (final skill in assets.skills) {
      final target = root.fileSystem.directory(p.join(root.path, skill.name));
      final document = _skillDocument(skill, filesRoot: filesRoot);
      changes
        ..add(
          PlannedChange(
            file: target.fileSystem.file(p.join(target.path, 'SKILL.md')),
            bytes: _expandSkillDir(utf8.encode(document), target),
            harness: harness,
          ),
        )
        ..addAll(_bundledFiles(skill, target, notes, harness: harness));
    }
    changes.addAll(
      _pluginFiles(assets.paths, filesRoot, notes, harness: harness),
    );

    return TranslationResult(changes: changes, notes: notes);
  }

  /// The variable Claude Code expands to a skill's own directory.
  ///
  /// No other harness expands it, so each copy spells out the directory it
  /// was written to, or a skill that runs its own scripts points nowhere.
  static const _claudeSkillDir = r'${CLAUDE_SKILL_DIR}';

  /// Rebuilds `SKILL.md` from the portable frontmatter and the body, with
  /// the plugin root the body names spelled out as its copy under
  /// [filesRoot].
  ///
  /// Claude-only keys were already dropped at parse time, so what is rendered
  /// here is the open Agent Skills key set and nothing else.
  String _skillDocument(SkillAsset skill, {required Directory filesRoot}) {
    final frontmatter = Frontmatter.render(skill.portableFrontmatter);
    final body = expandPluginFiles(skill.body, filesRoot: filesRoot);
    return '$frontmatter\n$body';
  }

  /// Plans a copy of every file under each of [paths] in [filesRoot], one
  /// folder per plugin, and each file once however many paths name it.
  ///
  /// Copied byte for byte: a script such as the FFCA plugin's
  /// `validate_layers.dart` runs as its plugin ships it.
  List<PlannedChange> _pluginFiles(
    List<PluginPath> paths,
    Directory filesRoot,
    List<TranslationNote> notes, {
    required Harness? harness,
  }) {
    final changes = <String, PlannedChange>{};
    for (final MapEntry(key: plugin, value: named)
        in paths.groupListsBy((path) => path.plugin).entries) {
      if (!isSafePluginName(plugin)) {
        notes.add(
          TranslationNote(
            subject: plugin,
            reason:
                'its name is not safe as a folder name, so the files its '
                'skills and agents name were not installed',
          ),
        );
        continue;
      }

      for (final path in named) {
        _copyPath(
          path,
          filesRoot.childDirectory(plugin),
          changes,
          notes,
          harness: harness,
        );
      }
    }
    return changes.values.toList();
  }

  /// Adds the copy in [copy] of each file [path] names to [changes], by
  /// target path, unless another path already named it.
  void _copyPath(
    PluginPath path,
    Directory copy,
    Map<String, PlannedChange> changes,
    List<TranslationNote> notes, {
    required Harness? harness,
  }) {
    for (final entity in _filesAt(path, notes)) {
      final relative = p.relative(entity.path, from: path.pluginRoot.path);
      final file = copy.fileSystem.file(p.join(copy.path, relative));
      if (changes.containsKey(file.path)) continue;

      final source = entity.copySource('${path.plugin}/$relative', notes);
      if (source == null) continue;
      changes[file.path] = PlannedChange(
        file: file,
        bytes: source.readAsBytesSync(),
        harness: harness,
        source: source,
      );
    }
  }

  /// The files [path] names: every one below it for a folder, or the one it
  /// is. A path the plugin does not hold is reported in [notes].
  List<FileSystemEntity> _filesAt(
    PluginPath path,
    List<TranslationNote> notes,
  ) {
    final fileSystem = path.pluginRoot.fileSystem;
    final at = p.joinAll([path.pluginRoot.path, ...path.path.split('/')]);
    // followLinks is off so a symlinked directory is reported rather than
    // walked, which a cycle would otherwise turn into a hang.
    final type = fileSystem.typeSync(at, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      notes.add(
        TranslationNote(
          subject: '${path.plugin}/${path.path}',
          reason:
              'the plugin does not hold it, so the skills and agents that '
              'name it point at nothing',
        ),
      );
      return const [];
    }
    if (type == FileSystemEntityType.directory) {
      return fileSystem
          .directory(at)
          .listSync(recursive: true, followLinks: false)
          .where((entity) => entity is! Directory)
          .toList();
    }
    return [
      if (type == FileSystemEntityType.link)
        fileSystem.link(at)
      else
        fileSystem.file(at),
    ];
  }

  /// Plans everything under the skill's directory except its `SKILL.md`.
  ///
  /// `references/`, `scripts/`, and the flat `reference.md` two skills use all
  /// travel with the skill. Built eagerly, so every note lands in [notes]
  /// before [translate] returns them.
  List<PlannedChange> _bundledFiles(
    SkillAsset skill,
    Directory target,
    List<TranslationNote> notes, {
    required Harness? harness,
  }) {
    // The parser only builds a skill from a directory holding a SKILL.md, so
    // this is not the normal case. A plugin cache cleared between resolution
    // and translation is, and it should report rather than throw a raw
    // FileSystemException out of `install`.
    if (!skill.directory.existsSync()) {
      notes.add(
        TranslationNote(
          subject: skill.name,
          reason:
              'its directory ${skill.directory.path} has gone away, so '
              'only the SKILL.md was written',
        ),
      );
      return const [];
    }

    // followLinks is off so a symlinked directory is reported rather than
    // walked, which a cycle would otherwise turn into a hang.
    final entities = skill.directory.listSync(
      recursive: true,
      followLinks: false,
    );

    final changes = <PlannedChange>[];
    for (final entity in entities) {
      if (entity is Directory) continue;

      final relative = p.relative(entity.path, from: skill.directory.path);
      if (relative == 'SKILL.md') continue;

      final source = entity.copySource('${skill.name}/$relative', notes);
      if (source == null) continue;

      changes.add(
        PlannedChange(
          file: target.fileSystem.file(p.join(target.path, relative)),
          bytes: _expandSkillDir(source.readAsBytesSync(), target),
          harness: harness,
          source: source,
        ),
      );
    }
    return changes;
  }

  /// [bytes] with [_claudeSkillDir] spelled out as [target]'s path.
  ///
  /// Every file a skill ships goes through here, `SKILL.md` included, so this
  /// is the one place that knows the variable. A file that is not UTF-8
  /// text, such as an image, is copied untouched.
  List<int> _expandSkillDir(List<int> bytes, Directory target) {
    try {
      return utf8.encode(
        utf8.decode(bytes).replaceAll(_claudeSkillDir, target.path),
      );
    } on FormatException {
      return bytes;
    }
  }
}
