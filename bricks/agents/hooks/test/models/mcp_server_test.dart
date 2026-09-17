import 'package:hooks/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('McpServer.fromVars', () {
    test('coerces a local server with command, args, and env', () {
      final server = McpServer.fromVars({
        'command': 'dart',
        'args': ['mcp-server'],
        'env': {'TOKEN': 'abc123'},
      });

      expect(server.command, 'dart');
      expect(server.args, ['mcp-server']);
      expect(server.env, {'TOKEN': 'abc123'});
      expect(server.url, isNull);
      expect(server.isRemote, isFalse);
    });

    test('coerces a remote server from a url', () {
      final server = McpServer.fromVars({'url': 'https://mcp.example.com'});

      expect(server.url, 'https://mcp.example.com');
      expect(server.isRemote, isTrue);
      expect(server.command, isNull);
      expect(server.args, isEmpty);
      expect(server.env, isEmpty);
    });

    test('defaults args and env when missing or malformed', () {
      final server = McpServer.fromVars({
        'command': 'dart',
        'args': null,
        'env': 'not a map',
      });

      expect(server.args, isEmpty);
      expect(server.env, isEmpty);
    });

    test('ignores a non-string url', () {
      final server = McpServer.fromVars({'url': 42});

      expect(server.url, isNull);
      expect(server.isRemote, isFalse);
    });
  });
}
