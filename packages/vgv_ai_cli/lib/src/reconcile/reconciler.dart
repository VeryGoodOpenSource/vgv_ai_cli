import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';
import 'package:vgv_ai_cli/src/reconcile/applied_change.dart';
import 'package:vgv_ai_cli/src/reconcile/markdown_sections.dart';
import 'package:vgv_ai_cli/src/reconcile/toml_edits.dart';

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
    final existed = manifest.existsSync();
    final loaded = _loadManifest(manifest, existed: existed);
    final run = _Run(force: force, dryRun: dryRun, hashes: {...loaded});

    final applied = [for (final change in changes) run.guarded(change)];
    if (dryRun || _hashesEquality.equals(loaded, run.hashes)) return applied;

    // The manifest is VGV's alone, so it is written outright.
    final contents = _encodeJson(run.hashes);
    try {
      _write(manifest, utf8.encode(contents), existed: existed);
      return applied;
    } on FileSystemException catch (error) {
      final change = PlannedChange.text(
        file: manifest,
        contents: contents,
        harness: null,
      );
      return [...applied, _failed(change, error)];
    }
  }

  Map<String, String> _loadManifest(File manifest, {required bool existed}) {
    final decoded = existed ? _decodeJson(manifest.readAsStringSync()) : null;
    return {
      for (final MapEntry(:key, :value) in (decoded ?? const {}).entries)
        if (value is String) key: value,
    };
  }
}

const _encoder = JsonEncoder.withIndent('  ');

const _deepEquality = DeepCollectionEquality();

const _bytesEquality = ListEquality<int>();

const _hashesEquality = MapEquality<String, String>();

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
      return _failed(change, error);
    }
  }

  AppliedChange _apply(PlannedChange change) {
    final file = change.file;
    final existed = file.existsSync();
    final original = existed ? file.readAsBytesSync() : const <int>[];

    final (:bytes, :held) = switch (change.mode) {
      ChangeMode.own => _own(change, existed ? original : null),
      _ => _mergeText(change, original),
    };

    final changed = !_bytesEquality.equals(bytes, original);
    if (changed && !dryRun) {
      _write(file, bytes, existed: existed, source: change.source);
    }
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
        _bytesEquality.equals(original, change.bytes) ||
        hashes[change.file.path] == _hash(original);
    return ours
        ? (bytes: change.bytes, held: _Held.nothing)
        : (bytes: original, held: _Held.userValue);
  }

  /// Merges [change] into the text of [original] in its mode's format.
  ({List<int> bytes, _Held held}) _mergeText(
    PlannedChange change,
    List<int> original,
  ) {
    final String text;
    try {
      text = utf8.decode(original);
    } on FormatException {
      return (bytes: original, held: _Held.unparseable);
    }

    final incoming = change.contents;
    final merge = switch (change.mode) {
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
      _ => (
        contents: upsertSection(text, change.section!, incoming),
        held: _Held.nothing,
      ),
    };
    return (bytes: utf8.encode(merge.contents), held: merge.held);
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

  /// Writes [merged] into [original] as TOML text, so the user's comments,
  /// layout and unrelated keys survive.
  ///
  /// Two edits are tried in turn, and the first that parses back to exactly
  /// [merged] is kept. Appending what [merged] adds covers new tables and
  /// arrays of tables. Upserting each key that changed covers a key added to
  /// a table the user already has, or a value VGV replaces. Re-serializing
  /// drops every comment, so it happens only when neither works and forced.
  String? _rewriteToml(
    String original,
    Map<String, dynamic> existing,
    Map<String, dynamic> merged,
  ) {
    Iterable<String> edits() sync* {
      final additions = _encodeToml(_missing(existing, merged));
      yield '${original.trimRight()}\n\n$additions';
      yield _upsertChanged(original, existing, merged);
    }

    final edited = edits().firstWhereOrNull(
      (edit) => _deepEquality.equals(_decodeToml(edit), merged),
    );
    return edited ?? (force ? _encodeToml(merged) : null);
  }

  /// [text] with every value [merged] holds that [existing] does not
  /// upserted into [table], and every table under it.
  String _upsertChanged(
    String text,
    Map<String, dynamic> existing,
    Map<String, dynamic> merged, {
    List<String> table = const [],
  }) {
    var edited = text;
    for (final MapEntry(:key, :value) in merged.entries) {
      final before = existing[key];
      if (value is Map<String, dynamic>) {
        edited = _upsertChanged(
          edited,
          before is Map<String, dynamic> ? before : const {},
          value,
          table: [...table, key],
        );
      } else if (!_deepEquality.equals(before, value)) {
        edited = upsertTomlKey(edited, table: table, key: key, value: value);
      }
    }
    return edited;
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

/// Writes [bytes] to [file], through a symlink and keeping its permissions.
///
/// The bytes go to a temporary file beside the target and are published by
/// rename, so an interrupted run cannot leave a half-written config behind.
/// The temporary file starts as a copy of the target, or of [source] when
/// there is no target yet, because a copy carries the file mode across.
void _write(File file, List<int> bytes, {required bool existed, File? source}) {
  final target = existed
      ? file.fileSystem.file(file.resolveSymbolicLinksSync())
      : file;
  target.parent.createSync(recursive: true);
  final temp = target.fileSystem.file('${target.path}.vgv-tmp');

  try {
    (existed ? target : source)?.copySync(temp.path);
    temp
      ..writeAsBytesSync(bytes, flush: true)
      ..renameSync(target.path);
  } on FileSystemException {
    if (temp.existsSync()) temp.deleteSync();
    rethrow;
  }
}

/// Reports [change] as failed with [error], rather than throwing it.
AppliedChange _failed(PlannedChange change, FileSystemException error) =>
    AppliedChange(
      change: change,
      outcome: ChangeOutcome.failed,
      error: [error.message, ?error.osError?.message].join(': '),
    );

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
