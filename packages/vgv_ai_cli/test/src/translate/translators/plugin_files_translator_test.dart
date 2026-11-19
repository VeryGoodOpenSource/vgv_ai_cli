import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

void main() {
  group(PluginFilesTranslator, () {
    const ffca = PluginRef(
      name: 'ffca',
      repo: 'acme/ffca',
      version: '0.1.3',
      gitRef: 'v0.1.3',
    );

    late FileSystem fs;
    late Directory plugin;
    late ProjectScope scope;

    setUp(() {
      fs = MemoryFileSystem.test();
      plugin = fs.directory('/cache/ffca')..createSync(recursive: true);
      scope = ProjectScope(fs.directory('/work/app'));
    });

    void write(String path, String contents) => fs.file('/cache/ffca/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

    TranslationResult translate(List<String> entries) =>
        const PluginFilesTranslator().translate(
          plugins: [
            PluginDirectory(
              plugin: ffca,
              directory: plugin,
              referencedEntries: entries,
            ),
          ],
          scope: scope,
        );

    List<String> paths(TranslationResult result) =>
        [for (final change in result.changes) change.file.path]..sort();

    test('copies every file of a referenced folder under the plugin root', () {
      write('references/a.md', 'a');
      write('references/deep/b.md', 'b');

      final result = translate(['references']);

      expect(paths(result), [
        '/work/app/.vgv_ai/plugins/ffca@v0.1.3/references/a.md',
        '/work/app/.vgv_ai/plugins/ffca@v0.1.3/references/deep/b.md',
      ]);
      expect(result.changes.first.contents, 'a');
      expect(result.notes, isEmpty);
    });

    test('copies nothing the bodies do not reference', () {
      write('references/a.md', 'a');
      write('evals/big.json', '{}');
      write('README.md', '# ffca');

      expect(paths(translate(['references'])), [
        '/work/app/.vgv_ai/plugins/ffca@v0.1.3/references/a.md',
      ]);
    });

    test('copies a referenced file at the plugin root', () {
      write('setup.sh', 'echo');

      expect(paths(translate(['setup.sh'])), [
        '/work/app/.vgv_ai/plugins/ffca@v0.1.3/setup.sh',
      ]);
    });

    test('shares the copy, owned by no harness, from its source', () {
      write('scripts/run.sh', 'echo');

      final change = translate(['scripts']).changes.single;

      expect(change.harness, isNull);
      expect(change.mode, ChangeMode.own);
      expect(change.source?.path, '/cache/ffca/scripts/run.sh');
    });

    test('materializes a symlinked file', () {
      write('shared/x.md', 'shared');
      fs.link('/cache/ffca/references/x.md')
        ..parent.createSync(recursive: true)
        ..createSync('/cache/ffca/shared/x.md');
      fs.link('/cache/ffca/notes.md').createSync('/cache/ffca/shared/x.md');

      final result = translate(['references', 'notes.md']);

      expect(result.changes.map((c) => c.contents), ['shared', 'shared']);
    });

    test('notes a broken symlink instead of copying it', () {
      fs.link('/cache/ffca/references/gone.md')
        ..parent.createSync(recursive: true)
        ..createSync('/cache/ffca/nowhere.md');

      final result = translate(['references']);

      expect(result.changes, isEmpty);
      expect(result.notes.single.subject, 'ffca/references/gone.md');
    });

    test('notes a referenced entry the plugin does not have', () {
      final result = translate(['scripts']);

      expect(result.changes, isEmpty);
      expect(result.notes.single.subject, 'ffca/scripts');
    });

    test('copies nothing for a plugin that references nothing', () {
      write('references/a.md', 'a');

      expect(translate(const []).changes, isEmpty);
    });
  });
}
