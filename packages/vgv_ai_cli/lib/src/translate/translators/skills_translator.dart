import 'dart:convert';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// {@template skills_translator}
/// Writes a copy of the skills under one root: the shared one most harnesses
/// read, or a harness's own.
///
/// Not a `HarnessTranslator`, because the shared copy belongs to no single
/// harness.
/// {@endtemplate}
class const SkillsTranslator() {
  /// {@macro skills_translator}
  this;

  /// Plans every skill under [root], plus the files each one ships alongside
  /// its `SKILL.md`, owned by [harness] or shared when null.
  TranslationResult translate({
    required PluginAssets assets,
    required Directory root,
    Harness? harness,
  }) {
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    for (final skill in assets.skills) {
      final target = root.fileSystem.directory(p.join(root.path, skill.name));
      changes
        ..add(
          PlannedChange(
            file: target.fileSystem.file(p.join(target.path, 'SKILL.md')),
            bytes: _expandSkillDir(utf8.encode(_skillDocument(skill)), target),
            harness: harness,
          ),
        )
        ..addAll(_bundledFiles(skill, target, notes, harness: harness));
    }

    return TranslationResult(changes: changes, notes: notes);
  }

  /// The variable Claude Code expands to a skill's own directory.
  ///
  /// No other harness expands it, so each copy spells out the directory it
  /// was written to, or a skill that runs its own scripts points nowhere.
  static const _claudeSkillDir = r'${CLAUDE_SKILL_DIR}';

  /// Rebuilds `SKILL.md` from the portable frontmatter and the body.
  ///
  /// Claude-only keys were already dropped at parse time, so what is rendered
  /// here is the open Agent Skills key set and nothing else.
  String _skillDocument(SkillAsset skill) {
    final frontmatter = Frontmatter.render(skill.portableFrontmatter);
    return '$frontmatter\n${skill.body}';
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
