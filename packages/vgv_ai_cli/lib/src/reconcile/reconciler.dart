import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Opening marker for the generated instruction block.
const blockBegin = '<!-- vgv:begin -->';

/// Closing marker for the generated instruction block.
const blockEnd = '<!-- vgv:end -->';

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Applies [PlannedChange]s to disk.
///
/// `install` writes into a home directory full of config the user owns, so
/// every mode here is designed to be non-destructive: JSON and TOML are merged
/// rather than replaced, markdown is edited only between the markers, and any
/// file that is about to change is backed up first.
class Reconciler {
  /// Creates a [Reconciler].
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

    final updated = switch (change.mode) {
      ChangeMode.own => change.contents,
      ChangeMode.block => _mergeBlock(original, change.contents),
      ChangeMode.mergeJson => _mergeJson(original, change.contents),
      ChangeMode.mergeToml => _mergeToml(original, change.contents),
    };

    if (existed && updated == original) {
      return AppliedChange(change: change, outcome: ChangeOutcome.unchanged);
    }

    if (dryRun) {
      logger.detail('Would write ${file.path}');
      return AppliedChange(
        change: change,
        outcome: existed ? ChangeOutcome.updated : ChangeOutcome.created,
      );
    }

    File? backup;
    if (existed) backup = _backup(file);

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(updated);

    return AppliedChange(
      change: change,
      outcome: existed ? ChangeOutcome.updated : ChangeOutcome.created,
      backup: backup,
    );
  }

  File _backup(File file) {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '');
    final backup = File('${file.path}.vgv-backup-$stamp')
      ..writeAsStringSync(file.readAsStringSync());
    logger.detail('Backed up ${file.path} to ${backup.path}');
    return backup;
  }

  /// Replaces the region between the markers, appending the block when the
  /// file has none. Content outside the markers is untouched.
  String _mergeBlock(String original, String block) {
    if (original.isEmpty) return '$block\n';

    final start = original.indexOf(blockBegin);
    final end = original.indexOf(blockEnd);
    if (start == -1 || end == -1 || end < start) {
      final separator = original.endsWith('\n') ? '\n' : '\n\n';
      return '$original$separator$block\n';
    }

    final before = original.substring(0, start);
    final after = original.substring(end + blockEnd.length);
    return '$before${block.trim()}$after';
  }

  String _mergeJson(String original, String incoming) {
    final addition = jsonDecode(incoming);
    if (original.trim().isEmpty) return '${_jsonEncoder.convert(addition)}\n';

    final Object? existing;
    try {
      existing = jsonDecode(original);
    } on FormatException catch (_) {
      // Refuse to silently discard a file we cannot parse.
      logger.warn('Could not parse JSON; leaving it alone.');
      return original;
    }

    if (existing is! Map || addition is! Map) return original;
    final merged = _deepMerge(
      Map<String, dynamic>.from(existing),
      Map<String, dynamic>.from(addition),
    );
    return '${_jsonEncoder.convert(merged)}\n';
  }

  /// Merges [addition] into [base].
  ///
  /// Maps recurse, lists union while keeping order, and scalars keep the
  /// existing value unless [force] is set. Keeping the user's scalar is the
  /// safe default: their model choice or approval mode should survive an
  /// install.
  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> addition,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final MapEntry(:key, :value) in addition.entries) {
      final existing = result[key];
      if (existing == null) {
        result[key] = value;
      } else if (existing is Map && value is Map) {
        result[key] = _deepMerge(
          Map<String, dynamic>.from(existing),
          Map<String, dynamic>.from(value),
        );
      } else if (existing is List && value is List) {
        result[key] = <dynamic>[
          ...existing,
          ...value.where((v) => !existing.contains(v)),
        ];
      } else if (force) {
        result[key] = value;
      }
    }
    return result;
  }

  /// Appends whole TOML tables that are not already present.
  ///
  /// Only table-level granularity is supported. Editing inside an existing
  /// table would need a real TOML parser, and declining to touch a table the
  /// user already wrote is the safer behaviour anyway.
  String _mergeToml(String original, String incoming) {
    if (incoming.trim().isEmpty || incoming.trimLeft().startsWith('#')) {
      return original;
    }
    if (original.trim().isEmpty) return '${incoming.trim()}\n';

    final existingTables = RegExp(
      r'^\s*\[([^\]]+)\]',
      multiLine: true,
    ).allMatches(original).map((m) => m.group(1)!.trim()).toSet();

    final additions = <String>[];
    for (final table in incoming.trim().split(RegExp(r'\n\s*\n'))) {
      final name = RegExp(r'^\s*\[([^\]]+)\]').firstMatch(table)?.group(1);
      if (name == null) continue;
      if (existingTables.contains(name.trim())) {
        logger.detail('Leaving existing TOML table [$name] alone');
        continue;
      }
      additions.add(table.trim());
    }

    if (additions.isEmpty) return original;
    final separator = original.endsWith('\n') ? '\n' : '\n\n';
    return '$original$separator${additions.join('\n\n')}\n';
  }
}
