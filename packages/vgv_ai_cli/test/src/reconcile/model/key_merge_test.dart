import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/model/model.dart';

Matcher _keyMerge({
  required bool writes,
  required Object? value,
  required bool adds,
  required Object? added,
  required bool declined,
}) => isA<KeyMerge>()
    .having((m) => m.writes, 'writes', writes)
    .having((m) => m.value, 'value', value)
    .having((m) => m.adds, 'adds', adds)
    .having((m) => m.added, 'added', added)
    .having((m) => m.declined, 'declined', declined);

void main() {
  group('KeyMerge', () {
    test('added writes the value and adds all of it', () {
      expect(
        const KeyMerge.added('vgv'),
        _keyMerge(
          writes: true,
          value: 'vgv',
          adds: true,
          added: 'vgv',
          declined: false,
        ),
      );
    });

    test('added adds a null value too', () {
      expect(
        const KeyMerge.added(null),
        _keyMerge(
          writes: true,
          value: null,
          adds: true,
          added: null,
          declined: false,
        ),
      );
    });

    test('replaced writes the value and adds nothing', () {
      expect(
        const KeyMerge.replaced('vgv'),
        _keyMerge(
          writes: true,
          value: 'vgv',
          adds: false,
          added: null,
          declined: false,
        ),
      );
    });

    test('table writes the merged table and adds what it gained', () {
      const inner = DeepMerge(
        merged: {'a': 1, 'b': 2},
        added: {'b': 2},
        declined: true,
      );

      expect(
        KeyMerge.table(inner),
        _keyMerge(
          writes: true,
          value: {'a': 1, 'b': 2},
          adds: true,
          added: {'b': 2},
          declined: true,
        ),
      );
    });

    test('table adds nothing when the table gained nothing', () {
      const inner = DeepMerge(merged: {'a': 1}, added: {}, declined: false);

      expect(KeyMerge.table(inner).adds, isFalse);
    });

    test('union appends the gained entries and adds them', () {
      expect(
        KeyMerge.union(['a'], ['b']),
        _keyMerge(
          writes: true,
          value: ['a', 'b'],
          adds: true,
          added: ['b'],
          declined: false,
        ),
      );
    });

    test('union adds nothing when no entry was gained', () {
      expect(KeyMerge.union(['a'], const []).adds, isFalse);
    });

    test('kept writes nothing and reports whether it declined', () {
      expect(
        const KeyMerge.kept(declined: true),
        _keyMerge(
          writes: false,
          value: null,
          adds: false,
          added: null,
          declined: true,
        ),
      );
    });
  });
}
