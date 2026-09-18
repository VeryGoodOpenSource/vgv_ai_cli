import 'dart:io';

/// {@template reconciler}
/// Reconciles a single staged config file into the user's real config.
///
/// Each config format (JSON, TOML, markdown) has its own reconciler so the
/// `install` command can merge or overwrite per file without branching on the
/// extension itself.
/// {@endtemplate}
abstract interface class Reconciler {
  /// Reconciles [staged] into [destination], creating [destination] when it
  /// does not yet exist.
  Future<void> reconcile({required File staged, required File destination});
}
