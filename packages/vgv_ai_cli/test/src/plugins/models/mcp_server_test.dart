import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/models/mcp_server.dart';

void main() {
  group('McpServer', () {
    group('fromJson', () {
      test('parses a local server', () {
        final server = McpServer.fromJson({
          'command': 'dart',
          'args': ['mcp-server', '--enable', 'dart_format'],
          'env': {'TOKEN': 'abc'},
        });

        expect(server.command, 'dart');
        expect(server.args, ['mcp-server', '--enable', 'dart_format']);
        expect(server.env, {'TOKEN': 'abc'});
        expect(server.url, isNull);
        expect(server.isRemote, isFalse);
      });

      test('parses a remote server', () {
        final server = McpServer.fromJson({
          'url': 'https://mcp.context7.com/mcp',
        });

        expect(server.url, 'https://mcp.context7.com/mcp');
        expect(server.isRemote, isTrue);
        expect(server.command, isNull);
        expect(server.args, isEmpty);
        expect(server.env, isEmpty);
      });

      test('coerces malformed fields rather than throwing', () {
        final server = McpServer.fromJson({
          'command': 42,
          'args': ['ok', 7],
          'env': {'A': 1},
          'url': false,
        });

        expect(server.command, isNull);
        expect(server.args, ['ok', '7']);
        expect(server.env, {'A': 1});
        expect(server.url, isNull);
      });
    });

    group('toVars', () {
      test('omits empty and null fields for a local server', () {
        const server = McpServer(command: 'very_good', args: ['mcp']);

        expect(server.toVars(), {
          'command': 'very_good',
          'args': ['mcp'],
        });
      });

      test('emits only url for a remote server', () {
        const server = McpServer(url: 'https://mcp.context7.com/mcp');

        expect(server.toVars(), {'url': 'https://mcp.context7.com/mcp'});
      });

      test('round-trips through fromJson', () {
        final server = McpServer.fromJson({
          'command': 'dart',
          'args': ['mcp-server'],
          'env': {'K': 'v'},
        });

        expect(server.toVars(), {
          'command': 'dart',
          'args': ['mcp-server'],
          'env': {'K': 'v'},
        });
      });
    });
  });
}
