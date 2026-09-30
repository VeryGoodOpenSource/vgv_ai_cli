import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/document/contribution.dart';

void main() {
  group('isManaged', () {
    test('is true only for a key VGV contributed and nobody changed', () {
      final managed = {'theme': 'vgv'};

      expect(isManaged(managed, 'theme', 'vgv'), isTrue);
      expect(isManaged(managed, 'theme', 'mine'), isFalse);
      expect(isManaged(managed, 'model', 'vgv'), isFalse);
    });
  });

  group('contributionOf', () {
    test('owns every key that is new', () {
      expect(contributionOf({'mine': 1}, {'mine': 1, 'theme': 'vgv'}, {}), {
        'theme': 'vgv',
      });
    });

    test('keeps owning a key it contributed that the user left alone', () {
      expect(
        contributionOf({'theme': 'vgv'}, {'theme': 'vgv 2'}, {'theme': 'vgv'}),
        {'theme': 'vgv 2'},
      );
    });

    test('gives up a key the user changed', () {
      expect(
        contributionOf({'theme': 'mine'}, {'theme': 'mine'}, {'theme': 'vgv'}),
        isEmpty,
      );
    });

    test('owns only its part of a table the user has', () {
      expect(
        contributionOf(
          {
            'mcp': {'mine': 1},
          },
          {
            'mcp': {'mine': 1, 'dart': 2},
          },
          {},
        ),
        {
          'mcp': {'dart': 2},
        },
      );
    });

    test('owns the entries it appended to a list, and those it owned', () {
      expect(
        contributionOf(
          {
            'allow': ['Read', 'Bash'],
          },
          {
            'allow': ['Read', 'Bash', 'Edit'],
          },
          {
            'allow': ['Bash'],
          },
        ),
        {
          'allow': ['Bash', 'Edit'],
        },
      );
    });

    test('owns nothing of a scalar the user had, or of an empty part', () {
      expect(
        contributionOf(
          {
            'model': 'pro',
            'allow': ['Read'],
          },
          {
            'model': 'pro',
            'allow': ['Read'],
          },
          {},
        ),
        isEmpty,
      );
    });
  });

  group('compareContribution', () {
    test('finds nothing when the document holds all of it', () {
      final (:missing, :drifted) = compareContribution(
        {
          'mcp': {'dart': 'dart'},
          'allow': ['Bash'],
        },
        {
          'mcp': {'dart': 'dart', 'mine': 1},
          'allow': ['Read', 'Bash'],
        },
      );

      expect(missing, isEmpty);
      expect(drifted, isEmpty);
    });

    test('names each key path that is gone or changed', () {
      final (:missing, :drifted) = compareContribution(
        {
          'theme': 'vgv',
          'mcp': {'dart': 'dart', 'gh': 'gh'},
          'allow': ['Bash'],
        },
        {
          'theme': 'mine',
          'mcp': {'dart': 'dart'},
          'allow': ['Read'],
        },
      );

      expect(missing, ['mcp.gh', 'allow']);
      expect(drifted, ['theme']);
    });
  });

  group('subtractContribution', () {
    test("removes VGV's keys and entries, and the tables they empty", () {
      final (:remaining, :kept) = subtractContribution(
        {
          'mine': 1,
          'mcp': {'dart': 'dart'},
          'allow': ['Read', 'Bash'],
        },
        {
          'mcp': {'dart': 'dart'},
          'allow': ['Bash'],
          'gone': true,
        },
        force: false,
      );

      expect(remaining, {
        'mine': 1,
        'allow': ['Read'],
      });
      expect(kept, isFalse);
    });

    test('keeps a value the user changed, unless forced', () {
      final current = {'theme': 'mine'};
      final contribution = {'theme': 'vgv'};

      final unforced = subtractContribution(
        current,
        contribution,
        force: false,
      );
      final forced = subtractContribution(current, contribution, force: true);

      expect(unforced.remaining, current);
      expect(unforced.kept, isTrue);
      expect(forced.remaining, isEmpty);
      expect(forced.kept, isFalse);
    });
  });
}
