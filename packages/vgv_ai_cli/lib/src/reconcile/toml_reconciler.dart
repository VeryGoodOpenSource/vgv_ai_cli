import 'dart:io';

import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/reconcile/json_merge.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

/// {@template toml_reconciler}
/// Reconciles Codex's `config.toml` by parsing both sides to maps, deep-merging
/// the staged VGV output onto the user's file, and re-serializing.
///
/// Codex config is CLI-managed, so re-serializing (which drops comments and
/// normalizes formatting) is acceptable. User-only keys are preserved and
/// VGV-owned keys win on conflict, exactly as for JSON (see [deepMergeJson]).
/// {@endtemplate}
class const TomlReconciler() implements Reconciler {
  @override
  Future<void> reconcile({
    required File staged,
    required File destination,
  }) async {
    final overlay = TomlDocument.parse(await staged.readAsString()).toMap();
    final base = destination.existsSync()
        ? TomlDocument.parse(await destination.readAsString()).toMap()
        : const <String, dynamic>{};

    final merged = deepMergeJson(
      Map<String, dynamic>.from(base),
      Map<String, dynamic>.from(overlay),
    );

    await destination.create(recursive: true);
    await destination.writeAsString('${TomlDocument.fromMap(merged)}');
  }
}
