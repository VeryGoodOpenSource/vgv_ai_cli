import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group(DocumentCodec, () {
    const codec = DocumentCodec();

    test('compares structurally and byte by byte by default', () {
      expect(codec.deepEquality, isA<DeepCollectionEquality>());
      expect(codec.bytesEquality.equals([1, 2], [1, 2]), isTrue);
      expect(codec.bytesEquality.equals([1, 2], [2, 1]), isFalse);
    });

    group('decodeUtf8', () {
      test('decodes UTF-8, and is null for anything else', () {
        expect(codec.decodeUtf8(utf8.encode('héllo')), 'héllo');
        expect(codec.decodeUtf8([0xff, 0xfe]), isNull);
      });
    });

    group('mergesEntries', () {
      test('merges every list but an argv entry by entry', () {
        expect(codec.mergesEntries('instructions'), isTrue);
        expect(codec.mergesEntries('PreToolUse'), isTrue);
        expect(codec.mergesEntries('command'), isFalse);
        expect(codec.mergesEntries('args'), isFalse);
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
          codec.listContains(list, {
            'type': 'command',
            'args': ['a'],
          }),
          isTrue,
        );
        expect(codec.listContains(list, {'type': 'command'}), isFalse);
      });

      test('compares with the equality it was given', () {
        const unordered = DocumentCodec(
          deepEquality: DeepCollectionEquality.unordered(),
        );

        expect(
          unordered.listContains(
            [
              [1, 2],
            ],
            [2, 1],
          ),
          isTrue,
        );
        expect(
          codec.listContains(
            [
              [1, 2],
            ],
            [2, 1],
          ),
          isFalse,
        );
      });
    });
  });
}
