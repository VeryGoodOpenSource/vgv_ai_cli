import 'dart:convert';

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

    for (final skill in assets.skills) {
      final target = root.fileSystem.directory(p.join(root.path, skill.name));
      final document = _skillDocument(skill, skillsRoot: root);
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
      _pluginFiles(
        assets.paths,
        pluginFilesRoot(root),
        notes,
        harness: harness,
      ),
    );

    return TranslationResult(changes: changes, notes: notes);
  }

  /// The variable Claude Code expands to a skill's own directory.
  ///
  /// No other harness expands it, so each copy spells out the directory it
  /// was written to, or a skill that runs its own scripts points nowhere.
  static const _claudeSkillDir = r'${CLAUDE_SKILL_DIR}';

  /// Rebuilds `SKILL.md` from the portable frontmatter and the body, the
  /// body pointing at the plugin files beside [skillsRoot].
  ///
  /// Claude-only keys were already dropped at parse time, so what is rendered
  /// here is the open Agent Skills key set and nothing else.
  String _skillDocument(SkillAsset skill, {required Directory skillsRoot}) {
    final frontmatter = Frontmatter.render(skill.portableFrontmatter);
    final body = expandPluginFiles(skill.body, skillsRoot: skillsRoot);
    return '$frontmatter\n$body';
  }

  /// Plans a copy of each file [paths] name in [filesRoot], one folder per
  /// plugin, copied byte for byte so a script runs as its plugin ships it.
  List<PlannedChange> _pluginFiles(
    List<PluginPath> paths,
    Directory filesRoot,
    List<TranslationNote> notes, {
    required Harness? harness,
  }) {
    // A file a folder and its own path both name is copied once.
    final named = <String>{};
    return [
      for (final path in paths)
        ..._copies(
          _filesAt(path, notes).where((entity) => named.add(entity.path)),
          from: path.pluginRoot,
          to: filesRoot.childDirectory(path.plugin),
          subject: path.plugin,
          notes: notes,
          harness: harness,
        ),
    ];
  }

  /// The files [path] names: every one below it for a folder, or the one it
  /// is. A path the plugin does not hold is reported in [notes].
  List<FileSystemEntity> _filesAt(
    PluginPath path,
    List<TranslationNote> notes,
  ) {
    final fileSystem = path.pluginRoot.fileSystem;
    final absolute = p.joinAll([path.pluginRoot.path, ...path.path.split('/')]);
    return switch (fileSystem.typeSync(absolute, followLinks: false)) {
      FileSystemEntityType.notFound => _missing(path, notes),
      FileSystemEntityType.directory =>
        fileSystem.directory(absolute).filesBelow(),
      FileSystemEntityType.link => [fileSystem.link(absolute)],
      _ => [fileSystem.file(absolute)],
    };
  }

  /// Reports in [notes] that the plugin does not hold [path].
  List<FileSystemEntity> _missing(
    PluginPath path,
    List<TranslationNote> notes,
  ) {
    notes.add(
      TranslationNote(
        subject: path.id,
        reason:
            'the plugin does not hold it, so the skills and agents that name '
            'it point at nothing',
      ),
    );
    return const [];
  }

  /// Plans everything under the skill's directory except its `SKILL.md`.
  ///
  /// `references/`, `scripts/`, and the flat `reference.md` two skills use all
  /// travel with the skill.
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

    final document = skill.directory.childFile('SKILL.md').path;
    return _copies(
      skill.directory.filesBelow().where((entity) => entity.path != document),
      from: skill.directory,
      to: target,
      subject: skill.name,
      notes: notes,
      harness: harness,
      bytes: (bytes) => _expandSkillDir(bytes, target),
    );
  }

  /// Plans a copy in [to] of each of [entities], at its path relative to
  /// [from], holding what [bytes] makes of its contents. One that cannot be
  /// copied is reported in [notes] under [subject].
  ///
  /// Built eagerly, so every note lands in [notes] before [translate]
  /// returns them.
  List<PlannedChange> _copies(
    Iterable<FileSystemEntity> entities, {
    required Directory from,
    required Directory to,
    required String subject,
    required List<TranslationNote> notes,
    required Harness? harness,
    List<int> Function(List<int> bytes) bytes = _verbatim,
  }) => [
    for (final entity in entities)
      if (_copyOf(entity, from: from, subject: subject, notes: notes)
          case final source?)
        PlannedChange(
          file: to.fileSystem.file(
            p.join(to.path, p.relative(entity.path, from: from.path)),
          ),
          bytes: bytes(source.readAsBytesSync()),
          harness: harness,
          source: source,
        ),
  ];

  /// The file a copy of [entity] reads from, or null, reported in [notes].
  static File? _copyOf(
    FileSystemEntity entity, {
    required Directory from,
    required String subject,
    required List<TranslationNote> notes,
  }) => entity.copySource(
    '$subject/${p.relative(entity.path, from: from.path)}',
    notes,
  );

  /// [bytes] as they are.
  static List<int> _verbatim(List<int> bytes) => bytes;

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
