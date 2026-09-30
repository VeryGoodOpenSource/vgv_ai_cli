import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/documents.dart';

void main() {
  group('hashBytes', () {
    test('is the hex SHA-256 of the bytes', () {
      expect(
        hashBytes(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('hashText', () {
    test('is the hex SHA-256 of the text as UTF-8', () {
      expect(hashText('abc'), hashBytes(utf8.encode('abc')));
    });
  });

  group('decodeUtf8', () {
    test('decodes UTF-8, and is null for anything else', () {
      expect(decodeUtf8(utf8.encode('héllo')), 'héllo');
      expect(decodeUtf8([0xff, 0xfe]), isNull);
    });
  });

  group('bytesEquality', () {
    test('compares contents byte by byte', () {
      expect(bytesEquality.equals([1, 2], [1, 2]), isTrue);
      expect(bytesEquality.equals([1, 2], [2, 1]), isFalse);
    });
  });

  group('listContains', () {
    test('finds an entry that is structurally equal', () {
      final list = [
        {
          'type': 'command',
          'args': ['a'],
        },
      ];

      expect(
        listContains(list, {
          'type': 'command',
          'args': ['a'],
        }),
        isTrue,
      );
      expect(listContains(list, {'type': 'command'}), isFalse);
    });
  });

  group('JSON', () {
    test('decodes an object', () {
      expect(decodeJson('{"a": [1]}'), {
        'a': [1],
      });
    });

    test('is null for malformed JSON or anything but an object', () {
      expect(decodeJson('{ "a": 1, // mine\n}'), isNull);
      expect(decodeJson('[1]'), isNull);
    });

    test('encodes indented, with a trailing newline', () {
      expect(encodeJson({'a': 1}), '{\n  "a": 1\n}\n');
    });
  });

  group('TOML', () {
    test('decodes a document', () {
      expect(decodeToml('[mcp.dart]\ncommand = "dart"\n'), {
        'mcp': {
          'dart': {'command': 'dart'},
        },
      });
    });

    test('is null for malformed TOML', () {
      expect(decodeToml('[unclosed'), isNull);
    });

    test('encodes with a single trailing newline', () {
      final encoded = encodeToml({'model': 'gpt'});

      expect(encoded, endsWith('\n'));
      expect(encoded, isNot(endsWith('\n\n')));
      expect(decodeToml(encoded), {'model': 'gpt'});
    });
  });

  group('writeAtomically', () {
    late FileSystem fileSystem;

    setUp(() => fileSystem = MemoryFileSystem.test());

    test('creates a file and the directories above it', () {
      final file = fileSystem.file('/home/dev/.codex/config.toml');

      writeAtomically(file, utf8.encode('a'), existed: false);

      expect(file.readAsStringSync(), 'a');
      expect(fileSystem.file('${file.path}.vgv-tmp').existsSync(), isFalse);
    });

    test('replaces a file that is there', () {
      final file = fileSystem.file('/settings.json')..writeAsStringSync('old');

      writeAtomically(file, utf8.encode('new'), existed: true);

      expect(file.readAsStringSync(), 'new');
    });

    test('writes through a symlink rather than replacing it', () {
      final real = fileSystem.file('/dotfiles/settings.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final link = fileSystem.link('/settings.json')..createSync(real.path);

      writeAtomically(
        fileSystem.file(link.path),
        utf8.encode('new'),
        existed: true,
      );

      expect(fileSystem.isLinkSync(link.path), isTrue);
      expect(real.readAsStringSync(), 'new');
    });

    test('removes its temporary file and rethrows when it fails', () {
      final blocked = fileSystem.directory('/blocked')..createSync();

      expect(
        () => writeAtomically(
          fileSystem.file(blocked.path),
          utf8.encode('a'),
          existed: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(fileSystem.file('/blocked.vgv-tmp').existsSync(), isFalse);
    });
  });

  group('deleteThrough', () {
    late FileSystem fileSystem;

    setUp(() => fileSystem = MemoryFileSystem.test());

    test('deletes a file', () {
      final file = fileSystem.file('/settings.json')..createSync();

      deleteThrough(file);

      expect(file.existsSync(), isFalse);
    });

    test('deletes a symlink and the file it links to', () {
      final real = fileSystem.file('/dotfiles/settings.json')
        ..createSync(recursive: true);
      final link = fileSystem.link('/settings.json')..createSync(real.path);

      deleteThrough(fileSystem.file(link.path));

      expect(fileSystem.isLinkSync(link.path), isFalse);
      expect(real.existsSync(), isFalse);
    });
  });

  group('describeError', () {
    test('is the message alone when there is no OS error', () {
      expect(
        describeError(const FileSystemException('Cannot open file')),
        'Cannot open file',
      );
    });

    test("adds the OS error's message", () {
      expect(
        describeError(
          const FileSystemException(
            'Cannot open file',
            '/a',
            OSError('Permission denied', 13),
          ),
        ),
        'Cannot open file: Permission denied',
      );
    });
  });
}
