import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_server_entry.dart';

void main() {
  group('mcpServerEntry', () {
    test('spells a local server, leaving out empty args and env', () {
      expect(
        mcpServerEntry(const LocalMCPServer(name: 'dart', command: 'dart')),
        {'command': 'dart'},
      );
    });

    test('keeps args and env when there are some', () {
      expect(
        mcpServerEntry(
          const LocalMCPServer(
            name: 'dart',
            command: 'dart',
            args: ['mcp-server'],
            env: {'TOKEN': 'x'},
          ),
        ),
        {
          'command': 'dart',
          'args': ['mcp-server'],
          'env': {'TOKEN': 'x'},
        },
      );
    });

    test('spells a remote server by its url', () {
      expect(
        mcpServerEntry(
          const RemoteMCPServer(name: 'docs', url: 'https://docs.example'),
        ),
        {'url': 'https://docs.example'},
      );
    });
  });
}
