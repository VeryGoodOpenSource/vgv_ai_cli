import 'dart:convert';

import 'package:file/file.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';

/// {@template change_mode}
/// How a [PlannedChange] lands on a file that may already exist.
///
/// A file VGV owns outright is replaced. A file the user shares with VGV is
/// merged, and each merge keeps the user's own values unless the reconciler
/// is forced.
/// {@endtemplate}
enum ChangeMode {
  /// VGV owns the file and writes it whole. A file at the same path that
  /// VGV did not write, or that the user has since edited, is theirs and is
  /// kept unless forced.
  own,

  /// Deep merged into a JSON object. Maps merge, lists union, and a scalar
  /// the user already set is kept unless forced.
  ///
  /// A merge that adds anything re-serializes the file with two-space
  /// indentation. Key order and values survive, but the user's own
  /// indentation does not.
  mergeJson,

  /// Deep merged into a TOML document with the same rules as [mergeJson].
  ///
  /// New tables are appended and changed keys are edited where they stand,
  /// so the user's comments and layout survive. Re-serializing the file
  /// drops its comments, so it happens only when forced, and only for a
  /// change neither edit can make.
  mergeToml,

  /// Written as a named section between VGV's markers in a markdown file,
  /// `<!-- vgv-ai-cli:NAME -->` and `<!-- /vgv-ai-cli:NAME -->`. Everything
  /// outside the markers belongs to the user and is kept, and each section is
  /// rewritten on its own, so several can share one file. Only
  /// [PlannedChange.markdown] makes a change in this mode, since it is the
  /// one that names the section.
  mergeMarkdown,
}

/// {@template planned_change}
/// One file `vgv_ai` intends to write, and how.
/// {@endtemplate}
class PlannedChange {
  /// {@macro planned_change}
  new({
    required this.file,
    required this.bytes,
    required this.harness,
    this.mode = ChangeMode.own,
    this.source,
  }) : section = null,
       assert(
         mode != ChangeMode.mergeMarkdown,
         'a markdown merge names its section, so use PlannedChange.markdown',
       );

  /// {@macro planned_change}
  ///
  /// Convenience for text, which is what every change but a copied skill
  /// file is.
  new text({
    required File file,
    required String contents,
    required Harness? harness,
    ChangeMode mode = ChangeMode.own,
  }) : this(
         file: file,
         bytes: utf8.encode(contents),
         harness: harness,
         mode: mode,
       );

  /// {@macro planned_change}
  ///
  /// A [ChangeMode.mergeMarkdown] change, which writes [contents] as the
  /// section of [file] named [section].
  new markdown({
    required this.file,
    required String contents,
    required this.harness,
    required String this.section,
  }) : bytes = utf8.encode(contents),
       mode = ChangeMode.mergeMarkdown,
       source = null;

  /// The file to write.
  final File file;

  /// What VGV contributes to [file], before any merge.
  ///
  /// Bytes rather than text, because a skill may ship a file that is not
  /// UTF-8.
  final List<int> bytes;

  /// How [bytes] lands on [file].
  final ChangeMode mode;

  /// Null when the change is shared rather than owned by one harness.
  final Harness? harness;

  /// The file [bytes] was copied from, whose permissions [file] takes when
  /// it is created, so a copied script stays executable.
  final File? source;

  /// The name of the section a [PlannedChange.markdown] change writes, and
  /// null for every other change.
  final String? section;

  /// [bytes] decoded as UTF-8. Every merged format is text.
  String get contents => utf8.decode(bytes);

  @override
  String toString() {
    final owner = harness?.name ?? 'shared';
    return '[${mode.name}] ($owner) ${file.path}';
  }
}
