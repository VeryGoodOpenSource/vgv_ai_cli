import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  group('Contribution', () {
    test('owns only a key it contributed that nobody changed', () {
      const managed = Contribution({'theme': 'vgv'});

      expect(managed.owns('theme', 'vgv'), isTrue);
      expect(managed.owns('theme', 'mine'), isFalse);
      expect(managed.owns('model', 'vgv'), isFalse);
    });

    test('is empty when it holds no keys, and writes them as JSON', () {
      expect(Contribution.none.isEmpty, isTrue);
      expect(const Contribution({'a': 1}).isEmpty, isFalse);
      expect(const Contribution({'a': 1}).toJson(), {'a': 1});
    });

    test('is within a table only what it contributed to that table', () {
      const managed = Contribution({
        'mcp': {'dart': 'vgv'},
        'theme': 'vgv',
      });

      expect(managed.within('mcp').keys, {'dart': 'vgv'});
      expect(managed.within('theme'), Contribution.none);
      expect(managed.within('model'), Contribution.none);
    });

    test('has appended to a list only the entries it contributed', () {
      const managed = Contribution({
        'allow': ['--vgv'],
        'theme': 'vgv',
      });

      expect(managed.appendedTo('allow'), ['--vgv']);
      expect(managed.appendedTo('theme'), isEmpty);
      expect(managed.appendedTo('model'), isEmpty);
    });

    group('of', () {
      test('owns every key that is new', () {
        expect(
          Contribution.of(
            {'mine': 1},
            {'mine': 1, 'theme': 'vgv'},
            Contribution.none,
          ).keys,
          {'theme': 'vgv'},
        );
      });

      test('keeps owning a key it contributed that the user left alone', () {
        expect(
          Contribution.of(
            {'theme': 'vgv'},
            {'theme': 'vgv 2'},
            const Contribution({'theme': 'vgv'}),
          ).keys,
          {'theme': 'vgv 2'},
        );
      });

      test('gives up a key the user changed', () {
        expect(
          Contribution.of(
            {'theme': 'mine'},
            {'theme': 'mine'},
            const Contribution({'theme': 'vgv'}),
          ).isEmpty,
          isTrue,
        );
      });

      test('owns only its part of a table the user has', () {
        expect(
          Contribution.of(
            {
              'mcp': {'mine': 1},
            },
            {
              'mcp': {'mine': 1, 'dart': 2},
            },
            Contribution.none,
          ).keys,
          {
            'mcp': {'dart': 2},
          },
        );
      });

      test('owns the entries it appended to a list, and those it owned', () {
        expect(
          Contribution.of(
            {
              'allow': ['Read', 'Bash'],
            },
            {
              'allow': ['Read', 'Bash', 'Edit'],
            },
            const Contribution({
              'allow': ['Bash'],
            }),
          ).keys,
          {
            'allow': ['Bash', 'Edit'],
          },
        );
      });

      test('owns no entry of an argv the user had, as of a scalar', () {
        expect(
          Contribution.of(
            {
              'command': ['mine'],
            },
            {
              'command': ['npx', 'vgv'],
            },
            Contribution.none,
          ).isEmpty,
          isTrue,
        );
      });

      test('owns nothing of a scalar the user had, or of an empty part', () {
        expect(
          Contribution.of(
            {
              'model': 'pro',
              'allow': ['Read'],
            },
            {
              'model': 'pro',
              'allow': ['Read'],
            },
            Contribution.none,
          ).isEmpty,
          isTrue,
        );
      });
    });

    group('compare', () {
      test('finds nothing when the document holds all of it', () {
        final drift =
            const Contribution({
              'mcp': {'dart': 'dart'},
              'allow': ['Bash'],
            }).compare({
              'mcp': {'dart': 'dart', 'mine': 1},
              'allow': ['Read', 'Bash'],
            });

        expect(drift.isEmpty, isTrue);
        expect(drift.missing, isEmpty);
        expect(drift.drifted, isEmpty);
      });

      test('names each key path that is gone or changed', () {
        final drift =
            const Contribution({
              'theme': 'vgv',
              'mcp': {'dart': 'dart', 'gh': 'gh'},
              'allow': ['Bash'],
            }).compare({
              'theme': 'mine',
              'mcp': {'dart': 'dart'},
              'allow': ['Read'],
            });

        expect(drift.isEmpty, isFalse);
        expect(drift.missing, ['mcp.gh', 'allow']);
        expect(drift.drifted, ['theme']);
      });

      test('names an argv that differs at all as changed', () {
        const contribution = Contribution({
          'command': ['npx', 'vgv'],
        });

        expect(
          contribution.compare({
            'command': ['mine', 'npx', 'vgv'],
          }).drifted,
          ['command'],
        );
        expect(
          contribution.compare({
            'command': ['npx', 'vgv'],
          }).isEmpty,
          isTrue,
        );
      });
    });

    group('subtract', () {
      test("removes VGV's keys and entries, and the tables they empty", () {
        final subtraction =
            const Contribution({
              'mcp': {'dart': 'dart'},
              'allow': ['Bash'],
              'gone': true,
            }).subtract({
              'mine': 1,
              'mcp': {'dart': 'dart'},
              'allow': ['Read', 'Bash'],
            }, force: false);

        expect(subtraction.remaining, {
          'mine': 1,
          'allow': ['Read'],
        });
        expect(subtraction.kept, isFalse);
      });

      test('keeps a value the user changed, unless forced', () {
        final current = {'theme': 'mine'};
        const contribution = Contribution({'theme': 'vgv'});

        final unforced = contribution.subtract(current, force: false);
        final forced = contribution.subtract(current, force: true);

        expect(unforced.remaining, current);
        expect(unforced.kept, isTrue);
        expect(forced.remaining, isEmpty);
        expect(forced.kept, isFalse);
      });

      test('removes an argv whole, or keeps it whole once changed', () {
        const contribution = Contribution({
          'args': ['mcp-server'],
        });

        expect(
          contribution.subtract({
            'args': ['mcp-server'],
          }, force: false).remaining,
          isEmpty,
        );

        final changed = contribution.subtract({
          'args': ['mcp-server', '--mine'],
        }, force: false);
        expect(changed.remaining, {
          'args': ['mcp-server', '--mine'],
        });
        expect(changed.kept, isTrue);
      });
    });
  });
}
