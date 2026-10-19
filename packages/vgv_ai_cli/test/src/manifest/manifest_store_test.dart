import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group(ManifestStore, () {
    const entry = OwnedFile(
      path: '/home/dev/.agents/skills/a/SKILL.md',
      owner: null,
      sha256: 'hash',
    );

    late FileSystem fileSystem;
    late ManifestStore store;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      store = ManifestStore(fileSystem.directory('/home/dev'));
    });

    test('keeps the manifest under ~/.vgv_ai', () {
      expect(store.file.path, '/home/dev/.vgv_ai/manifest.json');
    });

    test('loads an empty manifest when there is none', () {
      expect(store.load()!.entries, isEmpty);
    });

    test('loads what it saved', () {
      store.save(InstallManifest(const [entry]));

      expect(store.load(), InstallManifest(const [entry]));
    });

    test('writes paths relative to home, and reads them back absolute', () {
      store.save(InstallManifest(const [entry]));
      final moved = ManifestStore(fileSystem.directory('/Users/dev'));
      moved.file.parent.createSync(recursive: true);
      store.file.copySync(moved.file.path);

      expect(
        jsonDecode(store.file.readAsStringSync()),
        containsPair('entries', [
          containsPair('path', '.agents/skills/a/SKILL.md'),
        ]),
      );
      expect(
        moved.load()!.entries.single.path,
        '/Users/dev/.agents/skills/a/SKILL.md',
      );
    });

    test('loads null for a manifest a newer version wrote', () {
      store.file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'version': InstallManifest.version + 1}),
        );

      expect(store.load(), isNull);
    });

    test('deletes the manifest once nothing is left in it', () {
      store
        ..save(InstallManifest(const [entry]))
        ..save(InstallManifest());

      expect(store.file.existsSync(), isFalse);
    });

    test('writes nothing for an empty manifest when there is none', () {
      store.save(InstallManifest());

      expect(store.file.existsSync(), isFalse);
    });
  });
}
