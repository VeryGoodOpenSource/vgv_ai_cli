import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/cli/cli.dart';
import 'package:vgv_ai_cli/src/harness/harness.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_assets.dart';
import 'package:vgv_ai_cli/src/reconcile/planned_change.dart';

/// Configures Claude Code.
///
/// Claude Code is the only harness that installs the plugins natively, so this
/// writes the marketplace wiring and the instruction block and nothing else.
/// Copying translated skills and agents here would duplicate what the plugin
/// system already does, and the two copies would drift.
class ClaudeHarness extends Harness {
  /// Creates a [ClaudeHarness].
  const new();

  @override
  String get name => 'claude';

  @override
  String get displayName => 'Claude Code';

  @override
  Future<bool> detected({required Logger logger}) =>
      ClaudeCli.installed(logger: logger);

  @override
  Directory configRoot(Directory home) =>
      Directory(p.join(home.path, '.claude'));

  @override
  List<PlannedChange> plan({
    required PluginAssets assets,
    required Directory home,
    required StagedOutput staged,
  }) {
    final root = configRoot(home);
    final changes = <PlannedChange>[];

    final settings = staged['claude_settings.fragment.json'];
    if (settings != null) {
      changes.add(
        merge(
          File(p.join(root.path, 'settings.json')),
          settings,
          ChangeMode.mergeJson,
        ),
      );
    }

    final block = staged['vgv_block.md'];
    if (block != null) {
      changes.add(
        merge(File(p.join(root.path, 'CLAUDE.md')), block, ChangeMode.block),
      );
    }

    return changes;
  }
}
