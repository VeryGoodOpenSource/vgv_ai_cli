import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

const _jsonEncoder = JsonEncoder.withIndent('  ');
const _jsonEquality = DeepCollectionEquality();
final _tableHeader = RegExp(r'^\s*\[([^\]]+)\]', multiLine: true);

/// What a merge produced: the content to write, and whether anything we wanted
/// to contribute was declined in favour of what the user already had.
typedef _Merge = ({String contents, bool declined});

/// A whole TOML table: its header name and the lines that belong to it.
typedef _Table = ({String name, String body});

/// {@template reconciler}
/// Applies [PlannedChange]s to disk.
///
/// `install` writes into a home directory full of config the user owns, so
/// every mode here is designed to be non-destructive: JSON and TOML are merged
/// rather than replaced. The only wholesale overwrite is [ChangeMode.own],
/// whose files VGV generates.
/// {@endtemplate}
class Reconciler {
  /// {@macro reconciler}
  const new({required this.logger, this.force = false, this.dryRun = false});

  /// Used for progress and diagnostics.
  final Logger logger;

  /// Whether our value wins a conflict with an existing one.
  final bool force;

  /// When true, nothing is written.
  final bool dryRun;

  /// Applies [changes] in order.
  List<AppliedChange> apply(List<PlannedChange> changes) {
    return [for (final change in changes) _applyOne(change)];
  }

  AppliedChange _applyOne(PlannedChange change) {
    final file = change.file;
    final existed = file.existsSync();
    final original = existed ? file.readAsStringSync() : '';

    final (:contents, :declined) = switch (change.mode) {
      ChangeMode.own => (contents: change.contents, declined: false),
      ChangeMode.mergeJson => _mergeJson(original, change.contents),
      ChangeMode.mergeToml => _mergeToml(original, change.contents),
    };

    if (contents == original) {
      return AppliedChange(
        change: change,
        outcome: declined ? ChangeOutcome.skipped : ChangeOutcome.unchanged,
      );
    }

    if (dryRun) {
      logger.detail('Would write ${file.path}');
      return AppliedChange(
        change: change,
        outcome: existed ? ChangeOutcome.updated : ChangeOutcome.created,
      );
    }

    file.parent.createSync(recursive: true);
    _write(file, contents);

    return AppliedChange(
      change: change,
      outcome: existed ? ChangeOutcome.updated : ChangeOutcome.created,
    );
  }

  /// Writes through a sibling temporary file to keep the swap atomic.
  ///
  /// A crash or interrupted in-place write would leave a truncated config.
  /// Renaming a fully written file over the target avoids that.
  void _write(File file, String contents) {
    File('${file.path}.vgv-tmp')
      ..writeAsStringSync(contents, flush: true)
      ..renameSync(file.path);
  }

  _Merge _mergeJson(String original, String incoming) {
    final Object? addition;
    try {
      addition = jsonDecode(incoming);
    } on FormatException catch (_) {
      // A malformed payload is our bug; don't damage the user's file over it.
      logger.warn('Could not parse the JSON to install; leaving it alone.');
      return (contents: original, declined: true);
    }

    if (original.trim().isEmpty) {
      return (contents: '${_jsonEncoder.convert(addition)}\n', declined: false);
    }

    final Object? existing;
    try {
      existing = jsonDecode(original);
    } on FormatException catch (_) {
      // Don't silently discard a file that can't be parsed.
      logger.warn('Could not parse JSON; leaving it alone.');
      return (contents: original, declined: true);
    }

    if (existing is! Map || addition is! Map) {
      return (contents: original, declined: true);
    }

    final merged = _deepMerge(
      Map<String, dynamic>.from(existing),
      Map<String, dynamic>.from(addition),
    );
    return (
      contents: '${_jsonEncoder.convert(merged.value)}\n',
      declined: merged.declined,
    );
  }

  /// Merges [addition] into [base].
  ///
  /// Maps recurse, lists union while keeping order, and scalars keep the
  /// existing value unless [force] is set. Keeping the user's scalar is the
  /// safe default so their settings survive an install.
  ({Map<String, dynamic> value, bool declined}) _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> addition,
  ) {
    final result = Map<String, dynamic>.from(base);
    var declined = false;
    for (final MapEntry(:key, :value) in addition.entries) {
      final existing = result[key];
      // An explicit null the user wrote is a choice, not an absent key.
      if (!result.containsKey(key)) {
        result[key] = value;
      } else if (existing is Map && value is Map) {
        final merged = _deepMerge(
          Map<String, dynamic>.from(existing),
          Map<String, dynamic>.from(value),
        );
        result[key] = merged.value;
        declined = declined || merged.declined;
      } else if (existing is List && value is List) {
        result[key] = <dynamic>[...existing, ..._missingFrom(existing, value)];
      } else if (force) {
        result[key] = value;
      } else {
        // A value that already matches ours is not a conflict.
        declined = declined || existing != value;
      }
    }
    return (value: result, declined: declined);
  }

  /// The entries of [addition] that [existing] does not already hold.
  ///
  /// JSON objects and arrays are compared by structure. `==` on a `Map` or a
  /// `List` is identity, so leaning on it would append a fresh copy of every
  /// hook and MCP server on each install.
  Iterable<dynamic> _missingFrom(
    List<dynamic> existing,
    List<dynamic> addition,
  ) {
    return addition.where(
      (value) => !existing.any((e) => _jsonEquality.equals(e, value)),
    );
  }

  /// Appends whole TOML tables that are not already present.
  ///
  /// Only table-level granularity is supported. Editing inside an existing
  /// table would need a real TOML parser, and declining to touch a table the
  /// user already wrote is the safer behaviour anyway.
  _Merge _mergeToml(String original, String incoming) {
    final tables = _tomlTables(incoming);
    if (tables.isEmpty) return (contents: original, declined: false);

    final existing = {
      for (final table in _tomlTables(original)) table.name: table.body,
    };

    final additions = <String>[];
    var declined = false;
    for (final table in tables) {
      if (existing.containsKey(table.name)) {
        logger.detail('Leaving existing TOML table [${table.name}] alone');
        // A table we wrote on an earlier install is not a conflict.
        declined = declined || existing[table.name] != table.body;
        continue;
      }
      additions.add(table.body);
    }

    if (additions.isEmpty) return (contents: original, declined: declined);

    final appended = '${additions.join('\n\n')}\n';
    if (original.trim().isEmpty) {
      return (contents: appended, declined: declined);
    }

    final separator = original.endsWith('\n') ? '\n' : '\n\n';
    return (contents: '$original$separator$appended', declined: declined);
  }

  /// Splits a TOML fragment into whole tables.
  ///
  /// A table runs from its header to the line before the next header, so
  /// tables written back to back are still seen as separate. Splitting on
  /// blank lines instead would name a run of tables after the first of them
  /// and either drop the rest or write a duplicate header.
  List<_Table> _tomlTables(String toml) {
    final lines = toml.trim().split('\n');
    final headers = [
      for (var i = 0; i < lines.length; i++)
        if (_tableHeader.hasMatch(lines[i])) i,
    ];

    final begins = [
      for (var i = 0; i < headers.length; i++)
        _startOf(lines, headers[i], i == 0 ? 0 : headers[i - 1] + 1),
    ];

    return [
      for (var i = 0; i < headers.length; i++)
        (
          name: _tableHeader.firstMatch(lines[headers[i]])!.group(1)!.trim(),
          body: lines
              .sublist(
                begins[i],
                i + 1 < begins.length ? begins[i + 1] : lines.length,
              )
              .join('\n')
              .trim(),
        ),
    ];
  }

  /// Where the table headed at [header] begins.
  ///
  /// Comment and blank lines written directly above a header belong to it, so
  /// a fragment that opens with a provenance comment still carries a table.
  int _startOf(List<String> lines, int header, int floor) {
    var start = header;
    while (start > floor && _isPrelude(lines[start - 1])) {
      start--;
    }
    return start;
  }

  bool _isPrelude(String line) {
    final trimmed = line.trim();
    return trimmed.isEmpty || trimmed.startsWith('#');
  }
}
