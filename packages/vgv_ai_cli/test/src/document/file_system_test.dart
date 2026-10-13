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

    test('deletes a file under a symlinked directory and keeps the link', () {
      final real = fileSystem.file('/dotfiles/claude/settings.json')
        ..createSync(recursive: true);
      final link = fileSystem.link('/home/.claude')
        ..createSync(real.parent.path, recursive: true);

      fileSystem.file('${link.path}/settings.json').deleteThrough();

      expect(real.existsSync(), isFalse);
      expect(fileSystem.isLinkSync(link.path), isTrue);
    });
  });

  group('deleteHere', () {
    test('deletes a file', () {
      final file = fileSystem.file('/settings.json')
        ..createSync()
        ..deleteHere();

      expect(file.existsSync(), isFalse);
    });

    test('deletes a symlink and keeps the file it links to', () {
      final real = fileSystem.file('/dotfiles/settings.json')
        ..createSync(recursive: true);
      final link = fileSystem.link('/settings.json')..createSync(real.path);

      fileSystem.file(link.path).deleteHere();

      expect(fileSystem.isLinkSync(link.path), isFalse);
      expect(real.existsSync(), isTrue);
    });
  });

  group('deleteEmptyUpTo', () {
    late Directory root;

    setUp(() => root = fileSystem.directory('/home/.agents/skills'));

    test('deletes empty directories up to the boundary and keeps it', () {
      fileSystem.directory('${root.path}/a/b')
        ..createSync(recursive: true)
        ..deleteEmptyUpTo(root);

      expect(fileSystem.directory('${root.path}/a').existsSync(), isFalse);
      expect(root.existsSync(), isTrue);
    });

    test('stops at the first directory that is not empty', () {
      final start = fileSystem.directory('${root.path}/a/b')
        ..createSync(recursive: true);
      final kept = fileSystem.file('${root.path}/a/user.md')..createSync();

      start.deleteEmptyUpTo(root);

      expect(start.existsSync(), isFalse);
      expect(kept.existsSync(), isTrue);
    });

    test('walks up past a directory that is already gone', () {
      fileSystem.directory('${root.path}/a').createSync(recursive: true);

      fileSystem.directory('${root.path}/a/b').deleteEmptyUpTo(root);

      expect(fileSystem.directory('${root.path}/a').existsSync(), isFalse);
      expect(root.existsSync(), isTrue);
    });

    test('does nothing for the boundary itself', () {
      root
        ..createSync(recursive: true)
        ..deleteEmptyUpTo(root);

      expect(root.existsSync(), isTrue);
    });

    test('does nothing for a directory outside the boundary', () {
      final outside = fileSystem.directory('/home/.codex')
        ..createSync(recursive: true)
        ..deleteEmptyUpTo(root);

      expect(outside.existsSync(), isTrue);
    });

    test('never deletes a symlinked directory', () {
      final real = fileSystem.directory('/dotfiles/skill')
        ..createSync(recursive: true);
      root.createSync(recursive: true);
      final link = fileSystem.link('${root.path}/skill')..createSync(real.path);

      fileSystem.directory(link.path).deleteEmptyUpTo(root);

      expect(fileSystem.isLinkSync(link.path), isTrue);
      expect(real.existsSync(), isTrue);
    });

    test('never deletes through a symlinked directory', () {
      final real = fileSystem.directory('/dotfiles/skill/references')
        ..createSync(recursive: true);
      root.createSync(recursive: true);
      final link = fileSystem.link('${root.path}/skill')
        ..createSync(real.parent.path);

      fileSystem.directory('${link.path}/references').deleteEmptyUpTo(root);

      expect(fileSystem.isLinkSync(link.path), isTrue);
      expect(real.existsSync(), isTrue);
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
