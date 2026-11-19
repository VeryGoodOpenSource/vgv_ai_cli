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
        scope: UserScope(home),
        selected: {harness},
      );

      expect(plan.harnesses.keys, [harness]);
      expect(plan.changes, isNotEmpty);
    });
  }

  group('plugin files in rendered bodies', () {
    /// The contents of every file [harness] renders rather than copies, which
    /// are the only ones carrying the rewritten plugin root.
    Future<List<String>> rendered(Harness harness) async {
      final plan = await const Translator().translate(
        assets: assets,
        scope: UserScope(home),
        selected: {harness},
      );
      return [
        for (final change in plan.changes)
          if (change.source == null) change.contents,
      ];
    }

    /// Every path under the plugin cache that [texts] name, without the
    /// punctuation that may close a sentence.
    Set<String> referenced(List<String> texts) {
      final cache = home.childDirectory('.vgv_ai').childDirectory('plugins');
      final path = RegExp(
        '${RegExp.escape(cache.path)}/[^\\s`\'")]*[^\\s`\'").,;:]',
      );
      return {
        for (final text in texts)
          for (final match in path.allMatches(text)) match[0]!,
      };
    }

    for (final harness in Harness.values.where((h) => h != Harness.claude)) {
      test('point ${harness.name} at plugin files that exist', () async {
        final texts = await rendered(harness);
        final paths = referenced(texts);

        expect(texts, everyElement(isNot(contains(r'${CLAUDE_PLUGIN_ROOT}'))));
        expect(paths, isNotEmpty);
        expect(
          paths.where(
            (path) =>
                home.fileSystem.typeSync(path) == FileSystemEntityType.notFound,
          ),
          isEmpty,
        );
      });
    }

    test('are left to Claude Code, which reads the plugin natively', () async {
      expect(referenced(await rendered(Harness.claude)), isEmpty);
    });
  });

  group('in a project', () {
    late ProjectScope project;
    late PluginAssets projectAssets;
    late List<PluginDirectory> plugins;

    setUpAll(() async {
      project = ProjectScope(home.childDirectory('project')..createSync());
      final resolution = await const PluginResolver().resolve(
        home,
        pluginRoot: project.pluginRoot,
      );
      (projectAssets, plugins) = switch (resolution) {
        ResolvedAssets(:final assets, :final directories) => (
          assets,
          directories,
        ),
        _ => fail('Could not resolve $vgvPlugins for a project'),
      };
    });

    Future<TranslationPlan> translate(Harness harness) =>
        const Translator().translate(
          assets: projectAssets,
          scope: project,
          selected: {harness},
          plugins: plugins,
        );

    /// Every planned file's contents that decode as text.
    List<String> texts(TranslationPlan plan) => [
      for (final change in plan.changes) ?_text(change),
    ];

    for (final harness in Harness.values) {
      test('writes ${harness.name} no absolute path', () async {
        final plan = await translate(harness);

        expect(plan.changes, isNotEmpty);
        expect(
          plan.changes.map((c) => c.file.path),
          everyElement(startsWith(project.root.path)),
        );
        expect(texts(plan), everyElement(isNot(contains(home.path))));
      });
    }

    for (final harness in Harness.values.where((h) => h != Harness.claude)) {
      test('points ${harness.name} at plugin files it copies', () async {
        final plan = await translate(harness);
        final planned = {
          for (final change in plan.changes)
            project.reference(change.file.path),
        };
        final copy = RegExp(
          '${RegExp.escape('.vgv_ai/plugins')}/[^\\s`\'")]*[^\\s`\'").,;:/]',
        );
        final copies = {
          for (final text in texts(plan))
            for (final match in copy.allMatches(text)) match[0]!,
        };

        expect(copies, isNotEmpty);
        expect(
          copies.where(
            (path) => !planned.any(
              (file) => file == path || file.startsWith('$path/'),
            ),
          ),
          isEmpty,
        );
      });
    }
  });
}

/// [change]'s contents, or null when they are not UTF-8 text.
String? _text(PlannedChange change) {
  try {
    return change.contents;
  } on FormatException {
    return null;
  }
}
