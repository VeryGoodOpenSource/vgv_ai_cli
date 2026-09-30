import 'dart:convert';

import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/document.dart';

void main() {
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
}
