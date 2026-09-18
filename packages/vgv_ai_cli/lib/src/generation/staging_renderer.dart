import 'dart:io';

import 'package:mason/mason.dart';
import 'package:vgv_ai_cli/src/templates/templates.dart';

/// {@template staging_renderer}
/// Renders the bundled `agents` brick into a staging directory.
///
/// Staging is deliberately separate from the user's real config: the brick
/// output is reconciled into place afterwards so user-owned keys survive. The
/// renderer runs the brick's pre-gen hook then generates, exactly as a `mason
/// make` would.
/// {@endtemplate}
class const StagingRenderer() {
  /// Renders the brick with [vars] into [target] and returns it.
  ///
  /// Existing files in [target] are overwritten; reconciliation against the
  /// real config happens later.
  Future<Directory> render({
    required Map<String, dynamic> vars,
    required Directory target,
  }) async {
    final generator = await MasonGenerator.fromBundle(agentsBundle);

    var resolved = vars;
    await generator.hooks.preGen(
      vars: resolved,
      onVarsChanged: (updated) => resolved = updated,
    );
    await generator.generate(
      DirectoryGeneratorTarget(target),
      vars: resolved,
      fileConflictResolution: FileConflictResolution.overwrite,
    );

    return target;
  }
}
