import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_exception.dart';

void main() {
  group('PluginException', () {
    test('every subclass reports its kind and formats itself', () {
      final cases = <PluginException, String>{
        const MissingPluginMetadata('/p'): 'MissingPluginMetadata',
        const InvalidPluginMetadata('/p', 'bad'): 'InvalidPluginMetadata',
        const NoAgentsFound('/p'): 'NoAgentsFound',
        const InvalidAgent('/p', 'bad'): 'InvalidAgent',
        const DuplicateAgentId('/p', 'bad'): 'DuplicateAgentId',
        const UnreadableFile('/p', 'bad'): 'UnreadableFile',
      };

      for (final entry in cases.entries) {
        expect(entry.key.kind, entry.value);
        expect(entry.key.path, '/p');
        expect(
          entry.key.toString(),
          '${entry.value}: /p: ${entry.key.message}',
        );
      }
    });

    test('supplies a default message where the path alone is enough', () {
      expect(
        const MissingPluginMetadata('/p').message,
        'no .claude-plugin/plugin.json found',
      );
      expect(
        const NoAgentsFound('/p').message,
        'no agents found under agents/',
      );
    });

    test('is an Exception, not an Error', () {
      expect(const NoAgentsFound('/p'), isA<Exception>());
      expect(const NoAgentsFound('/p'), isNot(isA<Error>()));
    });
  });
}
