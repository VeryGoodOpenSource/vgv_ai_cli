import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_tool_map.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/vgv_paths.dart';
import 'package:vgv_ai_cli/src/harness/translate/translation_result.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// {@template skills_translator}
/// Writes the one shared copy of the skills, not a per-harness copy.
///
/// Planned once rather than inside each translator, which is why it is not a
/// `HarnessTranslator`: the changes it produces belong to no single harness.
/// {@endtemplate}
class const SkillsTranslator() {
  /// Files whose contents are rewritten. Markdown carries the prose and the
  /// frontmatter that name MCP tools; a shell script does not, and rewriting a
  /// tool name inside one would corrupt it.
  static const _rewritableExtensions = {'.md'};

  /// Plans every skill, plus the files each one ships alongside its `SKILL.md`.
  TranslationResult translate({
    required PluginAssets assets,
    required Directory home,
  }) {
    final root = agentsSkillsRoot(home);
    final changes = <PlannedChange>[];
    final notes = <TranslationNote>[];

    for (final skill in assets.skills) {
      final target = root.fileSystem.directory(p.join(root.path, skill.name));
      changes
        ..add(
          PlannedChange.own(
            file: target.fileSystem.file(p.join(target.path, 'SKILL.md')),
            contents: _skillDocument(skill, notes),
            harness: null,
          ),
        )
        ..addAll(_bundledFiles(skill, target, notes));
    }

    return TranslationResult(changes: changes, notes: notes);
  }

  /// Rebuilds `SKILL.md` from the portable frontmatter and the body.
  ///
  /// Claude-only keys were already dropped at parse time, so what is rendered
  /// here is the open Agent Skills key set and nothing else.
  String _skillDocument(SkillAsset skill, List<TranslationNote> notes) {
    final frontmatter = Frontmatter.render(skill.portableFrontmatter);
    return _rewrite('$frontmatter\n${skill.body}', skill.name, notes);
  }

  /// Plans everything under the skill's directory except its `SKILL.md`.
  ///
  /// `references/`, `scripts/`, and the flat `reference.md` two skills use all
  /// travel with the skill.
  Iterable<PlannedChange> _bundledFiles(
    SkillAsset skill,
    Directory target,
    List<TranslationNote> notes,
  ) sync* {
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
      return;
    }

    // followLinks is off so a symlinked directory is reported rather than
    // walked, which a cycle would otherwise turn into a hang.
    final entities = skill.directory.listSync(
      recursive: true,
      followLinks: false,
    );

    for (final entity in entities) {
      if (entity is Directory) continue;

      final relative = p.relative(entity.path, from: skill.directory.path);
      if (relative == 'SKILL.md') continue;

      final source = _sourceFile(entity, skill.name, relative, notes);
      if (source == null) continue;

      final contents = _rewritableExtensions.contains(p.extension(relative))
          ? _rewrite(
              source.readAsStringSync(),
              '${skill.name}/$relative',
              notes,
            )
          : source.readAsStringSync();

      yield PlannedChange.own(
        file: target.fileSystem.file(p.join(target.path, relative)),
        contents: contents,
        harness: null,
      );
    }
  }

  /// Resolves [entity] to a readable file.
  ///
  /// Wingspan pools shared references under `skills/shared/` and symlinks them
  /// into each skill. `skills/shared` is not a skill and is never copied, so
  /// the link has to be materialized here or the copy lands broken.
  File? _sourceFile(
    FileSystemEntity entity,
    String skill,
    String relative,
    List<TranslationNote> notes,
  ) {
    if (entity is File) return entity;

    final String resolved;
    try {
      resolved = entity.resolveSymbolicLinksSync();
    } on FileSystemException {
      notes.add(
        TranslationNote(
          subject: '$skill/$relative',
          reason: 'the symlink points at something that does not exist',
        ),
      );
      return null;
    }

    final file = entity.fileSystem.file(resolved);
    if (file.existsSync()) return file;

    notes.add(
      TranslationNote(
        subject: '$skill/$relative',
        reason: 'the symlink points at a directory, which is not copied',
      ),
    );
    return null;
  }

  /// Rewrites MCP tool names, reporting any that have no CLI equivalent.
  String _rewrite(
    String contents,
    String subject,
    List<TranslationNote> notes,
  ) {
    for (final tool in McpToolMap.unmapped(contents)) {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'names $tool, which has no CLI equivalent, so Pi cannot '
              'run it',
        ),
      );
    }
    return McpToolMap.rewrite(contents);
  }
}
