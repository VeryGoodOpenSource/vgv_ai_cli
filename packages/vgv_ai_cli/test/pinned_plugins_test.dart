@Tags(['pinned-plugins', 'skip_very_good_optimization'])
library;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

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
        home: home,
        selected: {harness},
      );

      expect(plan.harnesses.keys, [harness]);
      expect(plan.changes, isNotEmpty);
    });

    test('points ${harness.name} at plugin files that exist', () async {
      final plan = await const Translator().translate(
        assets: assets,
        home: home,
        selected: {harness},
      );
      // Bodies are rendered, not copied, so only they carry the rewrite.
      final rendered = [
        for (final change in plan.changes)
          if (change.source == null) change.contents,
      ];
      final cache = home.childDirectory('.vgv_ai').childDirectory('plugins');
      final referenced = {
        for (final text in rendered)
          for (final match in RegExp(
            '${RegExp.escape(cache.path)}/[^\\s`\'")]+',
          ).allMatches(text))
            match[0]!,
      };

      expect(rendered, everyElement(isNot(contains(r'${CLAUDE_PLUGIN_ROOT}'))));
      expect(
        referenced.where(
          (path) =>
              home.fileSystem.typeSync(path) == FileSystemEntityType.notFound,
        ),
        isEmpty,
      );
      if (harness != Harness.claude) expect(referenced, isNotEmpty);
    });
  }
}
