import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/reconcile/json_merge.dart';

void main() {
  group('deepMergeJson', () {
    test('preserves user-only keys', () {
      final merged = deepMergeJson({'user': 1}, {'vgv': 2});

      expect(merged, {'user': 1, 'vgv': 2});
    });

    test('lets the overlay win on a leaf conflict', () {
      final merged = deepMergeJson({'shared': 'user'}, {'shared': 'vgv'});

      expect(merged, {'shared': 'vgv'});
    });

    test('merges nested maps recursively', () {
      final merged = deepMergeJson(
        {
          'mcpServers': {
            'user-server': {'command': 'mine'},
          },
        },
        {
          'mcpServers': {
            'dart': {'command': 'dart'},
          },
        },
      );

      expect(merged, {
        'mcpServers': {
          'user-server': {'command': 'mine'},
          'dart': {'command': 'dart'},
        },
      });
    });

    test('replaces lists wholesale rather than concatenating', () {
      final merged = deepMergeJson(
        {
          'instructions': ['USER.md', 'AGENTS.md'],
        },
        {
          'instructions': ['AGENTS.md'],
        },
      );

      expect(merged, {
        'instructions': ['AGENTS.md'],
      });
    });

    test('does not mutate the inputs', () {
      final base = {
        'nested': {'a': 1},
      };
      final overlay = {
        'nested': {'b': 2},
      };

      deepMergeJson(base, overlay);

      expect(base, {
        'nested': {'a': 1},
      });
      expect(overlay, {
        'nested': {'b': 2},
      });
    });
  });
}
