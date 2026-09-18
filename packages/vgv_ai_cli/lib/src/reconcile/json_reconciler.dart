import 'dart:convert';
import 'dart:io';

import 'package:vgv_ai_cli/src/reconcile/json_merge.dart';
import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

/// {@template json_reconciler}
/// Reconciles a JSON config file by deep-merging the staged VGV output onto the
/// user's existing file.
///
/// Backs the `claude`, `gemini`, `opencode`, and `pi` settings files. User-only
/// keys are preserved; VGV-owned keys win on conflict (see [deepMergeJson]).
/// {@endtemplate}
class const JsonReconciler({
  final JsonEncoder encoder = const JsonEncoder.withIndent('  '),
}) implements Reconciler {
  @override
  Future<void> reconcile({
    required File staged,
    required File destination,
  }) async {
    final overlay =
        jsonDecode(await staged.readAsString()) as Map<String, dynamic>;
    final base = destination.existsSync()
        ? jsonDecode(await destination.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{};

    final merged = deepMergeJson(base, overlay);

    await destination.create(recursive: true);
    await destination.writeAsString('${encoder.convert(merged)}\n');
  }
}
