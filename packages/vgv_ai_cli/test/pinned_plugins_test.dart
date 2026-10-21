@Tags(['pinned-plugins', 'skip_very_good_optimization'])
library;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';

/// Resolves the real pinned plugins over git, then parses and translates them
/// for every harness, so a pin that no longer resolves, parses or translates
/// fails before it merges.
void main() {
  late Directory home;
  late PluginAssets assets;

  setUpAll(() async {
    // An empty home, so the Claude Code cache misses and every plugin is
    // cloned at its pinned gitRef.
    home = const LocalFileSystem().systemTempDirectory.createTempSync(
      'pinned_plugins_test.',
    );

    final resolution = await const PluginResolver().resolve(home);
    assets = switch (resolution) {
      ResolvedAssets(:final assets) => assets,
      UnavailableAssets(:final plugin, :final reasons) => fail(
        'Could not resolve $plugin:\n${reasons.join('\n')}',
      ),
      UnparseableAssets(:final plugin, :final error) => fail(
        'Could not parse $plugin: $error',
      ),
    };
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  for (final harness in Harness.values) {
    test('translates $vgvPlugins for ${harness.name}', () async {
      final plan = await const Translator().translate(
        assets: assets,
        plugins: vgvPlugins,
        home: home,
        selected: {harness},
      );

      expect(plan.harnesses.keys, [harness]);
      expect(plan.changes, isNotEmpty);
    });
  }
}
