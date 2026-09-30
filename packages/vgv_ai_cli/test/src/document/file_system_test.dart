import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/document.dart';

void main() {
  late FileSystem fileSystem;

  setUp(() => fileSystem = MemoryFileSystem.test());

  group('writeAtomically', () {
    test('creates a file and the directories above it', () {
      final file = fileSystem.file('/home/dev/.codex/config.toml')
        ..writeAtomically(utf8.encode('a'), existed: false);

      expect(file.readAsStringSync(), 'a');
      expect(fileSystem.file('${file.path}.vgv-tmp').existsSync(), isFalse);
    });

    test('replaces a file that is there', () {
      final file = fileSystem.file('/settings.json')
        ..writeAsStringSync('old')
        ..writeAtomically(utf8.encode('new'), existed: true);

      expect(file.readAsStringSync(), 'new');
    });

    test('writes through a symlink rather than replacing it', () {
      final real = fileSystem.file('/dotfiles/settings.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final link = fileSystem.link('/settings.json')..createSync(real.path);

      fileSystem
          .file(link.path)
          .writeAtomically(utf8.encode('new'), existed: true);

      expect(fileSystem.isLinkSync(link.path), isTrue);
      expect(real.readAsStringSync(), 'new');
    });

    test('removes its temporary file and rethrows when it fails', () {
      final blocked = fileSystem.directory('/blocked')..createSync();

      expect(
        () => fileSystem
            .file(blocked.path)
            .writeAtomically(utf8.encode('a'), existed: false),
        throwsA(isA<FileSystemException>()),
      );
      expect(fileSystem.file('/blocked.vgv-tmp').existsSync(), isFalse);
    });
  });

  group('deleteThrough', () {
    test('deletes a file', () {
      final file = fileSystem.file('/settings.json')
        ..createSync()
        ..deleteThrough();

      expect(file.existsSync(), isFalse);
    });

    test('deletes a symlink and the file it links to', () {
      final real = fileSystem.file('/dotfiles/settings.json')
        ..createSync(recursive: true);
      final link = fileSystem.link('/settings.json')..createSync(real.path);

      fileSystem.file(link.path).deleteThrough();

      expect(fileSystem.isLinkSync(link.path), isFalse);
      expect(real.existsSync(), isFalse);
    });
  });

  group('description', () {
    test('is the message alone when there is no OS error', () {
      expect(
        const FileSystemException('Cannot open file').description,
        'Cannot open file',
      );
    });

    test("adds the OS error's message", () {
      expect(
        const FileSystemException(
          'Cannot open file',
          '/a',
          OSError('Permission denied', 13),
        ).description,
        'Cannot open file: Permission denied',
      );
    });
  });
}
