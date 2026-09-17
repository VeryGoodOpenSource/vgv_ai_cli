import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_agent.dart';

void main() {
  group('PluginAgent', () {
    group('normalizeStringList', () {
      test('returns empty for null', () {
        expect(PluginAgent.normalizeStringList(null), isEmpty);
      });

      test('splits a comma separated string', () {
        expect(
          PluginAgent.normalizeStringList('Read, Glob, mcp__dart__analyze'),
          ['Read', 'Glob', 'mcp__dart__analyze'],
        );
      });

      test('accepts a bare single-value string', () {
        expect(PluginAgent.normalizeStringList('Read'), ['Read']);
      });

      test('accepts a list', () {
        expect(PluginAgent.normalizeStringList(['bloc', 'testing']), [
          'bloc',
          'testing',
        ]);
      });

      test('stringifies non-string list entries', () {
        expect(PluginAgent.normalizeStringList([1, true]), ['1', 'true']);
      });

      test('drops empty and whitespace-only entries', () {
        expect(PluginAgent.normalizeStringList('a, ,,  b  '), ['a', 'b']);
        expect(PluginAgent.normalizeStringList(['', '  ', 'c']), ['c']);
      });

      test('returns empty for an unsupported shape', () {
        expect(PluginAgent.normalizeStringList(42), isEmpty);
        expect(PluginAgent.normalizeStringList({'a': 1}), isEmpty);
      });
    });

    test('defaults optional fields', () {
      final agent = PluginAgent(id: 'a', name: 'a', description: 'd');

      expect(agent.model, isNull);
      expect(agent.effort, isNull);
      expect(agent.body, isEmpty);
      expect(agent.skills, isEmpty);
      expect(agent.tools, isEmpty);
      expect(agent.extra, isEmpty);
    });

    test('exposes unmodifiable collections', () {
      final agent = PluginAgent(
        id: 'a',
        name: 'a',
        description: 'd',
        skills: ['one'],
        tools: ['Read'],
        extra: {'k': 'v'},
      );

      expect(() => agent.skills.add('two'), throwsUnsupportedError);
      expect(() => agent.tools.add('Bash'), throwsUnsupportedError);
      expect(() => agent.extra['other'] = 1, throwsUnsupportedError);
    });

    test('copies extra so later caller mutation does not leak in', () {
      final extra = <String, dynamic>{'k': 'v'};
      final agent = PluginAgent(
        id: 'a',
        name: 'a',
        description: 'd',
        extra: extra,
      );

      extra['added'] = true;

      expect(agent.extra, {'k': 'v'});
    });

    test('serializes every field', () {
      final agent = PluginAgent(
        id: 'nested/a',
        name: 'a',
        description: 'd',
        model: 'inherit',
        effort: 'medium',
        body: '# body',
        skills: ['bloc'],
        tools: ['Read'],
        extra: {'hooks': <String, dynamic>{}},
      );

      expect(agent.toJson(), {
        'id': 'nested/a',
        'name': 'a',
        'description': 'd',
        'model': 'inherit',
        'effort': 'medium',
        'skills': ['bloc'],
        'tools': ['Read'],
        'body': '# body',
        'extra': {'hooks': <String, dynamic>{}},
      });
    });
  });
}
