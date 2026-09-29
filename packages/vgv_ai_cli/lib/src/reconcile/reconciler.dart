import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

typedef _Merge = ({String contents, bool declined});

typedef _DeepMerge = ({Map<String, dynamic> merged, bool declined});

/// {@template reconciler}
/// Applies a [PlannedChange] to disk according to its [ChangeMode].
///
/// Without [force], a merge never replaces a value the user set, and a TOML
/// merge never re-serializes the user's file. With [dryRun], nothing is
/// written and each write is logged instead, but the outcome is the same.
/// {@endtemplate}
class const Reconciler({
  required final Logger logger,
  final JsonEncoder encoder = const JsonEncoder.withIndent('  '),
  final DeepCollectionEquality deepEquality = const DeepCollectionEquality(),
  final bool force = false,
  final bool dryRun = false,
}) {
  AppliedChange apply(PlannedChange change) {
    final file = change.file;
    final existed = file.existsSync();
    final original = existed ? file.readAsStringSync() : '';

    final merge = switch (change.mode) {
      ChangeMode.own => (contents: change.contents, declined: false),
      ChangeMode.mergeJson => _mergeDocument(
        original,
        change.contents,
        decode: _decodeJson,
        encode: _encodeJson,
        rewrite: (_, _, merged) => _encodeJson(merged),
      ),
      ChangeMode.mergeToml => _mergeDocument(
        original,
        change.contents,
        decode: _decodeToml,
        encode: _encodeToml,
        rewrite: _rewriteToml,
      ),
      ChangeMode.mergeMarkdown => (
        contents: _mergeBlock(original, change.contents),
        declined: false,
      ),
    };

    final changed = merge.contents != original;
    if (changed) _write(file, merge.contents);

    return AppliedChange(
      change: change,
      outcome: switch ((changed, existed, merge.declined)) {
        (false, _, true) => ChangeOutcome.skipped,
        (false, _, false) => ChangeOutcome.unchanged,
        (true, false, _) => ChangeOutcome.created,
        (true, true, true) => ChangeOutcome.partial,
        (true, true, false) => ChangeOutcome.updated,
      },
    );
  }

  /// Writes [contents] to [file], or only logs it on a dry run.
  void _write(File file, String contents) {
    if (dryRun) {
      logger.detail('Would write ${file.path}');
      return;
    }
    file.parent.createSync(recursive: true);
    // Write beside the target and publish by rename, so an interrupted run
    // cannot leave a half-written config behind.
    file.fileSystem.file('${file.path}.vgv-tmp')
      ..writeAsStringSync(contents, flush: true)
      ..renameSync(file.path);
  }

  /// Merges [incoming] into [original] using one format's codec.
  ///
  /// [rewrite] turns the merged document back into the file's contents, or
  /// returns null when it cannot do so without losing what the user wrote.
  _Merge _mergeDocument(
    String original,
    String incoming, {
    required Map<String, dynamic>? Function(String) decode,
    required String Function(Map<String, dynamic>) encode,
    required String? Function(
      String original,
      Map<String, dynamic> existing,
      Map<String, dynamic> merged,
    )
    rewrite,
  }) {
    final addition = decode(incoming);
    if (addition == null) return (contents: original, declined: true);

    if (original.trim().isEmpty) {
      return (contents: encode(addition), declined: false);
    }

    final existing = decode(original);
    if (existing == null) return (contents: original, declined: true);

    final deepMerged = _deepMerge(existing, addition, overwrite: force);

    if (deepEquality.equals(existing, deepMerged.merged)) {
      return (contents: original, declined: deepMerged.declined);
    }

    final contents = rewrite(original, existing, deepMerged.merged);
    if (contents == null) return (contents: original, declined: true);

    return (contents: contents, declined: deepMerged.declined);
  }

  /// Appends what [merged] adds to [original] as TOML text, so the user's
  /// comments and layout survive.
  ///
  /// The append is kept only when it parses back to exactly [merged]. A merge
  /// that edits a value or an inline array cannot be appended, and
  /// re-serializing drops every comment, so it happens only when forced.
  String? _rewriteToml(
    String original,
    Map<String, dynamic> existing,
    Map<String, dynamic> merged,
  ) {
    final additions = _encodeToml(_missing(existing, merged));
    final appended = '${original.trimRight()}\n\n$additions';
    if (deepEquality.equals(_decodeToml(appended), merged)) return appended;
    return force ? _encodeToml(merged) : null;
  }

  /// What [target] holds that [base] does not: every absent key, and the
  /// entries a list gained. [target] is a merge of [base], so a list it
  /// shares with [base] starts with [base]'s entries.
  Map<String, dynamic> _missing(
    Map<String, dynamic> base,
    Map<String, dynamic> target,
  ) {
    final missing = <String, dynamic>{};
    for (final MapEntry(:key, :value) in target.entries) {
      if (!base.containsKey(key)) {
        missing[key] = value;
        continue;
      }
      final gap = switch ((base[key], value)) {
        (
          final Map<dynamic, dynamic> existing,
          final Map<dynamic, dynamic> added,
        ) =>
          _missing(existing.cast(), added.cast()),
        (final List<dynamic> existing, final List<dynamic> added) =>
          added.sublist(existing.length),
        _ => const <Object>[],
      };
      if (gap case Map(isNotEmpty: true) || List(isNotEmpty: true)) {
        missing[key] = gap;
      }
    }
    return missing;
  }

  /// Opens the section of a markdown file that VGV manages.
  static const blockStart = '<!-- vgv_ai:start -->';

  /// Closes the section of a markdown file that VGV manages.
  static const blockEnd = '<!-- vgv_ai:end -->';

  /// Replaces VGV's delimited section of [original] with [incoming].
  ///
  /// An instructions file such as `~/.gemini/AGENTS.md` may already hold the
  /// user's own guidance, so everything outside the markers is theirs and is
  /// kept. The section is appended the first time.
  String _mergeBlock(String original, String incoming) {
    final block = '$blockStart\n${incoming.trimRight()}\n$blockEnd';
    final start = original.indexOf(blockStart);
    final end = start == -1 ? -1 : original.indexOf(blockEnd, start);

    if (end == -1) {
      final kept = original.trimRight();
      return kept.isEmpty ? '$block\n' : '$kept\n\n$block\n';
    }
    return original.replaceRange(start, end + blockEnd.length, block);
  }

  /// Decodes a JSON object, or null when it is malformed or not an object.
  Map<String, dynamic>? _decodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException catch (_) {
      return null;
    }
  }

  /// Encodes a decoded map back to canonical JSON with a trailing newline.
  String _encodeJson(Map<String, dynamic> map) {
    final json = encoder.convert(map);
    return '$json\n';
  }

  /// Decodes a TOML document, or null when it is malformed.
  Map<String, dynamic>? _decodeToml(String source) {
    try {
      return TomlDocument.parse(source).toMap();
    } on TomlException catch (_) {
      return null;
    }
  }

  /// Encodes a decoded map back to canonical TOML with a trailing newline.
  String _encodeToml(Map<String, dynamic> map) {
    final toml = TomlDocument.fromMap(map).toString().trim();
    return '$toml\n';
  }

  /// Merges [addition] into [base].
  _DeepMerge _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> addition, {
    required bool overwrite,
  }) {
    final result = Map<String, dynamic>.from(base);
    var declined = false;

    for (final MapEntry(:key, :value) in addition.entries) {
      final existing = result[key];

      if (!result.containsKey(key)) {
        result[key] = value;
        continue;
      }

      if (existing is Map && value is Map) {
        final merged = _deepMerge(
          existing.cast<String, dynamic>(),
          value.cast<String, dynamic>(),
          overwrite: overwrite,
        );
        result[key] = merged.merged;
        declined = declined || merged.declined;
        continue;
      }

      if (existing is List && value is List) {
        result[key] = <dynamic>[
          ...existing,
          ...value.where(
            (v) => !existing.any((e) => deepEquality.equals(e, v)),
          ),
        ];
        continue;
      }

      if (overwrite) {
        result[key] = value;
        continue;
      }

      declined = declined || existing != value;
    }

    return (merged: result, declined: declined);
  }
}
