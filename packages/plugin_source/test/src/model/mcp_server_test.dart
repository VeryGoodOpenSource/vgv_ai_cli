import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';

void main() {
  group(LocalMCPServer, () {
    test('spells itself as .mcp.json does, leaving out empty args and env', () {
      expect(const LocalMCPServer(name: 'dart', command: 'dart').toJson(), {
        'command': 'dart',
      });
    });

    test('keeps args and env when there are some', () {
      expect(
        const LocalMCPServer(
          name: 'dart',
          command: 'dart',
          args: ['mcp-server'],
          env: {'TOKEN': 'x'},
        ).toJson(),
        {
          'command': 'dart',
          'args': ['mcp-server'],
          'env': {'TOKEN': 'x'},
        },
      );
    });
  });

  group(RemoteMCPServer, () {
    test('spells itself by its url, leaving out empty headers', () {
      expect(
        const RemoteMCPServer(
          name: 'docs',
          url: 'https://docs.example',
        ).toJson(),
        {'url': 'https://docs.example'},
      );
    });

    test('keeps its headers when there are some', () {
      expect(
        const RemoteMCPServer(
          name: 'docs',
          url: 'https://docs.example',
          headers: {'Authorization': 'Bearer x'},
        ).toJson(),
        {
          'url': 'https://docs.example',
          'headers': {'Authorization': 'Bearer x'},
        },
      );
    });
  });
}
