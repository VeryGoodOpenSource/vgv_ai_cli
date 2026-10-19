import 'dart:convert';

import 'package:file/file.dart';
import 'package:toml/toml.dart';
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
  /// the user already set is kept unless forced. An argv, such as an MCP
  /// server's `command` or `args`, is one value, as a scalar is: see
  /// `DocumentCodec.mergesEntries`.
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
  mergeMarkdown;

  /// The format this mode merges into, or null when it does not merge into
  /// a document.
  DocumentFormat? get format => switch (this) {
    mergeJson => DocumentFormat.json,
    mergeToml => DocumentFormat.toml,
    own || mergeMarkdown => null,
  };
}

/// {@template document_format}
/// A structured document VGV merges keys into, and how it is read and
/// written.
/// {@endtemplate}
enum DocumentFormat {
  /// A JSON object.
  json,

  /// A TOML document.
  toml;

  /// The mode that merges into this format.
  ChangeMode get mode => switch (this) {
    json => ChangeMode.mergeJson,
    toml => ChangeMode.mergeToml,
  };

  /// Decodes [source], or returns null when it is malformed, or is JSON
  /// that is not an object.
  ///
  /// Gemini and OpenCode accept comments in their JSON settings, and a file
  /// that has them lands here as malformed. Rewriting it would drop the
  /// comments, so it is reported as unparseable for the user to edit by hand.
  Map<String, dynamic>? decode(String source) {
    try {
      return switch (this) {
        json => switch (jsonDecode(source)) {
          final Map<dynamic, dynamic> decoded =>
            decoded.cast<String, dynamic>(),
          _ => null,
        },
        toml => TomlDocument.parse(source).toMap(),
      };
    } on FormatException {
      return null;
    } on TomlException {
      return null;
    }
  }

  /// Encodes [document] back to canonical text with a trailing newline.
  String encode(Map<String, dynamic> document) => switch (this) {
    json => '${_jsonEncoder.convert(document)}\n',
    toml => '${TomlDocument.fromMap(document).toString().trim()}\n',
  };

  static const _jsonEncoder = JsonEncoder.withIndent('  ');
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
    ChangeMode mode = ChangeMode.own,
    this.source,
  }) : mode = mode == ChangeMode.mergeMarkdown
           ? throw ArgumentError.value(
               mode,
               'mode',
               'a markdown merge names its section, so use '
                   'PlannedChange.markdown',
             )
           : mode,
       section = null;

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

  /// The harness that owns the change, or null when it is shared.
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
