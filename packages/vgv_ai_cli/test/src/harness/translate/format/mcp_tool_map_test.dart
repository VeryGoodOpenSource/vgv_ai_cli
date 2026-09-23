import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/harness/translate/format/mcp_tool_map.dart';

void main() {
  group('McpToolMap.canonical', () {
    test('leaves a bare reference alone', () {
      expect(
        McpToolMap.canonical('mcp__dart__analyze_files'),
        'mcp__dart__analyze_files',
      );
    });

    test('strips the plugin prefix the marketplace generates', () {
      // The same tool is written both ways across the two plugins.
      expect(
        McpToolMap.canonical(
          'mcp__plugin_vgv-ai-flutter-plugin_dart__analyze_files',
        ),
        'mcp__dart__analyze_files',
      );
    });
  });

  group('McpToolMap.rewrite', () {
    test('replaces a mapped tool with its command', () {
      expect(
        McpToolMap.rewrite('Run mcp__dart__analyze_files first.'),
        'Run `dart analyze` first.',
      );
    });

    test('replaces a plugin-qualified reference too', () {
      expect(
        McpToolMap.rewrite('Use mcp__plugin_vgv-ai-flutter-plugin_dart__pub.'),
        'Use `dart pub`.',
      );
    });

    test('leaves an unmapped reference exactly as it is', () {
      // Left intact so unmapped can still find and report it.
      expect(
        McpToolMap.rewrite('Call mcp__unknown__thing now.'),
        'Call mcp__unknown__thing now.',
      );
    });

    test('replaces every occurrence', () {
      expect(
        McpToolMap.rewrite('mcp__dart__pub then mcp__dart__pub'),
        '`dart pub` then `dart pub`',
      );
    });

    test('leaves content with no references untouched', () {
      expect(McpToolMap.rewrite('Just prose.'), 'Just prose.');
    });
  });

  group('McpToolMap.unmapped', () {
    test('is empty when every reference maps', () {
      expect(
        McpToolMap.unmapped('mcp__dart__pub and mcp__very-good-cli__test'),
        isEmpty,
      );
    });

    test('reports only the references with no equivalent', () {
      expect(McpToolMap.unmapped('mcp__dart__pub and mcp__unknown__thing'), [
        'mcp__unknown__thing',
      ]);
    });

    test('deduplicates and sorts, so a report reads the same way twice', () {
      expect(McpToolMap.unmapped('mcp__z__b mcp__a__b mcp__z__b'), [
        'mcp__a__b',
        'mcp__z__b',
      ]);
    });
  });
}
