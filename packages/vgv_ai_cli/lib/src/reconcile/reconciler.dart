import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

class _Merge({required final String contents, required final bool declined});

class _DeepMergeResult({
  required final Map<String, dynamic> merged,
  required final bool declined,
});

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
      ChangeMode.own => _Merge(contents: change.contents, declined: false),
      ChangeMode.mergeJson => _mergeDocument(
        original,
        change.contents,
        decode: _decodeJson,
        encode: _encodeJson,
        overwrite: force,
      ),
      ChangeMode.mergeToml => _mergeDocument(
        original,
        change.contents,
        decode: _decodeToml,
        encode: _encodeToml,
        overwrite: true,
      ),
      ChangeMode.mergeMarkdown => _Merge(
        contents: _mergeBlock(original, change.contents),
        declined: false,
      ),
    };

    if (merge.contents == original) {
      return merge.declined
          ? AppliedChange.skipped(change: change)
          : AppliedChange.unchanged(change: change);
    }

    if (dryRun) {
      logger.detail('Would write ${file.path}');
    } else {
      file.parent.createSync(recursive: true);
      // Write beside the target and publish by rename, so an interrupted run
      // cannot leave a half-written config behind.
      file.fileSystem.file('${file.path}.vgv-tmp')
        ..writeAsStringSync(merge.contents, flush: true)
        ..renameSync(file.path);
    }

    return existed
        ? AppliedChange.updated(change: change)
        : AppliedChange.created(change: change);
  }

  /// Merges [incoming] into [original] using one format's codec.
  _Merge _mergeDocument(
    String original,
    String incoming, {
    required Map<String, dynamic>? Function(String) decode,
    required String Function(Map<String, dynamic>) encode,
    required bool overwrite,
  }) {
    final addition = decode(incoming);
    if (addition == null) return _Merge(contents: original, declined: true);

    if (original.trim().isEmpty) {
      return _Merge(contents: encode(addition), declined: false);
    }

    final existing = decode(original);
    if (existing == null) return _Merge(contents: original, declined: true);

    final deepMerged = _deepMerge(existing, addition, overwrite: overwrite);

    if (deepEquality.equals(existing, deepMerged.merged)) {
      return _Merge(contents: original, declined: deepMerged.declined);
    }

    return _Merge(
      contents: encode(deepMerged.merged),
      declined: deepMerged.declined,
    );
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
  _DeepMergeResult _deepMerge(
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

    return _DeepMergeResult(merged: result, declined: declined);
  }
}
