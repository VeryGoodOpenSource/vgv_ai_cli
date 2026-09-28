import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/applied_change.dart';

/// Where the reconciler records the files VGV owns under [home].
File installManifest(Directory home) =>
    home.fileSystem.file(p.join(home.path, '.vgv_ai', 'manifest.json'));

/// {@template reconciler}
/// Applies [PlannedChange]s to disk according to their [ChangeMode].
///
/// Without `force`, a merge never replaces a value the user set, a TOML
/// merge never re-serializes the user's file, and an owned file is never
/// written over a file VGV did not write or the user has since edited. With
/// `dryRun`, nothing is written, but the outcomes are the same.
/// {@endtemplate}
class const Reconciler() {
  /// Opens the section of a markdown file that VGV manages.
  static const blockStart = '<!-- vgv_ai:start -->';

  /// Closes the section of a markdown file that VGV manages.
  static const blockEnd = '<!-- vgv_ai:end -->';

  /// Applies every one of [changes] and returns what each did.
  ///
  /// [manifest] records a hash of every owned file this writes, which is how
  /// a later run tells VGV's files from the user's. A change that fails to
  /// read or write is reported as [ChangeOutcome.failed] and the rest still
  /// apply.
  List<AppliedChange> apply(
    List<PlannedChange> changes, {
    required File manifest,
    bool force = false,
    bool dryRun = false,
  }) {
    final hashes = _loadManifest(manifest);
    final recorded = {...hashes};
    final run = _Run(force: force, dryRun: dryRun, hashes: recorded);

    final applied = [for (final change in changes) run.guarded(change)];
    if (dryRun || _deepEquality.equals(hashes, recorded)) return applied;

    // The manifest is VGV's alone, so it is always forced, and what it
    // records about itself goes nowhere.
    final saved = _Run(force: true, dryRun: false, hashes: {}).guarded(
      PlannedChange.text(
        file: manifest,
        contents: _encodeJson(recorded),
        harness: null,
      ),
    );
    return [...applied, if (saved.outcome == ChangeOutcome.failed) saved];
  }

  Map<String, String> _loadManifest(File manifest) {
    final decoded = manifest.existsSync()
        ? _decodeJson(manifest.readAsStringSync())
        : null;
    return {
      for (final MapEntry(:key, :value) in (decoded ?? const {}).entries)
        if (value is String) key: value,
    };
  }
}

const _encoder = JsonEncoder.withIndent('  ');

const _deepEquality = DeepCollectionEquality();

typedef _Merge = ({String contents, _Held held});

typedef _DeepMerge = ({Map<String, dynamic> merged, bool declined});

/// What a merge left in place instead of taking VGV's.
enum _Held {
  /// Nothing: the file holds everything VGV contributes.
  nothing,

  /// A value, file or layout the user set.
  userValue,

  /// The whole file, because it could not be parsed.
  unparseable,
}

/// One [Reconciler.apply] call's settings, and the manifest it updates.
class _Run {
  new({required this.force, required this.dryRun, required this.hashes});

  final bool force;
  final bool dryRun;

  /// Owned file paths to the hash of what VGV last wrote there.
  final Map<String, String> hashes;

  /// Applies [change], reporting a filesystem error rather than throwing it.
  AppliedChange guarded(PlannedChange change) {
    try {
      return _apply(change);
    } on FileSystemException catch (error) {
      return AppliedChange(
        change: change,
        outcome: ChangeOutcome.failed,
        error: [error.message, ?error.osError?.message].join(': '),
      );
    }
  }

  AppliedChange _apply(PlannedChange change) {
    final file = change.file;
    final existed = file.existsSync();
    final original = existed ? file.readAsBytesSync() : const <int>[];

    final (:bytes, :held) = switch (change.mode) {
      ChangeMode.own => _own(change, existed ? original : null),
      final mode => _mergeText(mode, original, change.contents),
    };

    final changed = !_deepEquality.equals(bytes, original);
    if (changed && !dryRun) _write(file, bytes, source: change.source);
    if (change.mode == ChangeMode.own && held == _Held.nothing) {
      hashes[file.path] = _hash(bytes);
    }

    return AppliedChange(
      change: change,
      outcome: switch ((changed, existed, held)) {
        (false, _, _Held.userValue) => ChangeOutcome.skipped,
        (false, _, _Held.unparseable) => ChangeOutcome.unparseable,
        (false, _, _Held.nothing) => ChangeOutcome.unchanged,
        (true, false, _) => ChangeOutcome.created,
        (true, true, _Held.nothing) => ChangeOutcome.updated,
        (true, true, _) => ChangeOutcome.partial,
      },
    );
  }

  /// Decides whether VGV may write its owned file over [original].
  ///
  /// It may when there is nothing there, when what is there already matches,
  /// when it is exactly what VGV last wrote, or when forced. Anything else is
  /// the user's.
  ({List<int> bytes, _Held held}) _own(
    PlannedChange change,
    List<int>? original,
  ) {
    final ours =
        original == null ||
        force ||
        _deepEquality.equals(original, change.bytes) ||
        hashes[change.file.path] == _hash(original);
    return ours
        ? (bytes: change.bytes, held: _Held.nothing)
        : (bytes: original, held: _Held.userValue);
  }

  /// Merges [incoming] into the text of [original] in [mode]'s format.
  ({List<int> bytes, _Held held}) _mergeText(
    ChangeMode mode,
    List<int> original,
    String incoming,
  ) {
    final String text;
    try {
      text = utf8.decode(original);
    } on FormatException {
      return (bytes: original, held: _Held.unparseable);
    }

    final merge = switch (mode) {
      ChangeMode.mergeJson => _mergeDocument(
        text,
        incoming,
        decode: _decodeJson,
        encode: _encodeJson,
        rewrite: (_, _, merged) => _encodeJson(merged),
      ),
      ChangeMode.mergeToml => _mergeDocument(
        text,
        incoming,
        decode: _decodeToml,
        encode: _encodeToml,
        rewrite: _rewriteToml,
      ),
      _ => (contents: _mergeBlock(text, incoming), held: _Held.nothing),
    };
    return (bytes: utf8.encode(merge.contents), held: merge.held);
  }

  /// Writes [bytes] to [file], through a symlink and keeping its permissions.
  ///
  /// The bytes go to a temporary file beside the target and are published by
  /// rename, so an interrupted run cannot leave a half-written config behind.
  /// The temporary file starts as a copy of the target, or of [source] when
  /// there is no target yet, because a copy carries the file mode across.
  void _write(File file, List<int> bytes, {File? source}) {
    final target = file.existsSync()
        ? file.fileSystem.file(file.resolveSymbolicLinksSync())
        : file;
    target.parent.createSync(recursive: true);
    final temp = target.fileSystem.file('${target.path}.vgv-tmp');

    try {
      (target.existsSync() ? target : source)?.copySync(temp.path);
      temp
        ..writeAsBytesSync(bytes, flush: true)
        ..renameSync(target.path);
    } on FileSystemException {
      if (temp.existsSync()) temp.deleteSync();
      rethrow;
    }
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
    if (addition == null) return (contents: original, held: _Held.unparseable);

    if (original.trim().isEmpty) {
      return (contents: encode(addition), held: _Held.nothing);
    }

    final existing = decode(original);
    if (existing == null) return (contents: original, held: _Held.unparseable);

    final deepMerged = _deepMerge(existing, addition);
    final held = deepMerged.declined ? _Held.userValue : _Held.nothing;

    if (_deepEquality.equals(existing, deepMerged.merged)) {
      return (contents: original, held: held);
    }

    final contents = rewrite(original, existing, deepMerged.merged);
    if (contents == null) return (contents: original, held: _Held.userValue);

    return (contents: contents, held: held);
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
    if (_deepEquality.equals(_decodeToml(appended), merged)) return appended;
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

  /// Replaces VGV's delimited section of [original] with [incoming].
  ///
  /// An instructions file such as `~/.gemini/AGENTS.md` may already hold the
  /// user's own guidance, so everything outside the markers is theirs and is
  /// kept. The section is appended the first time.
  ///
  /// The end marker is paired with the start marker nearest before it, so a
  /// start marker left behind on its own never swallows the user's text
  /// between it and a later block.
  String _mergeBlock(String original, String incoming) {
    final block =
        '${Reconciler.blockStart}\n${incoming.trimRight()}\n'
        '${Reconciler.blockEnd}';
    final end = original.indexOf(Reconciler.blockEnd);
    final start = end == -1
        ? -1
        : original.lastIndexOf(Reconciler.blockStart, end);

    if (start == -1) {
      final kept = original.trimRight();
      return kept.isEmpty ? '$block\n' : '$kept\n\n$block\n';
    }
    return original.replaceRange(
      start,
      end + Reconciler.blockEnd.length,
      block,
    );
  }

  /// Merges [addition] into [base].
  _DeepMerge _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> addition,
  ) {
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
        );
        result[key] = merged.merged;
        declined = declined || merged.declined;
        continue;
      }

      if (existing is List && value is List) {
        result[key] = <dynamic>[
          ...existing,
          ...value.where(
            (v) => !existing.any((e) => _deepEquality.equals(e, v)),
          ),
        ];
        continue;
      }

      if (force) {
        result[key] = value;
        continue;
      }

      declined = declined || existing != value;
    }

    return (merged: result, declined: declined);
  }
}

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

/// Decodes a JSON object, or null when it is malformed or not an object.
///
/// Gemini and OpenCode accept comments in their JSON settings, and a file
/// that has them lands here as malformed. Rewriting it would drop the
/// comments, so it is reported as unparseable for the user to edit by hand.
Map<String, dynamic>? _decodeJson(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } on FormatException catch (_) {
    return null;
  }
}

/// Encodes a decoded map back to canonical JSON with a trailing newline.
String _encodeJson(Map<String, dynamic> map) => '${_encoder.convert(map)}\n';

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
