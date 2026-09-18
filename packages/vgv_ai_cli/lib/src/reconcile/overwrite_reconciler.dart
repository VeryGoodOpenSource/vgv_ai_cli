import 'dart:io';

import 'package:vgv_ai_cli/src/reconcile/reconciler.dart';

/// {@template overwrite_reconciler}
/// Reconciles a fully CLI-managed file by copying the staged output verbatim.
///
/// Backs the per-harness `AGENTS.md` files: their entire contents are generated
/// from the resolved plugins, so there is nothing user-owned to preserve and
/// the staged version simply replaces whatever is there.
/// {@endtemplate}
class const OverwriteReconciler() implements Reconciler {
  @override
  Future<void> reconcile({
    required File staged,
    required File destination,
  }) async {
    await destination.create(recursive: true);
    await staged.copy(destination.path);
  }
}
