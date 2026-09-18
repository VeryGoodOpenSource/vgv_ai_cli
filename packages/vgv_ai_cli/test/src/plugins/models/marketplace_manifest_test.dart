import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugins/models/marketplace_manifest.dart';

void main() {
  group('MarketplaceManifest', () {
    test('parses github plugins into sources', () {
      const content = '''
{
  "name": "very-good-claude-code-marketplace",
  "plugins": [
    {
      "name": "vgv-ai-flutter-plugin",
      "source": {
        "source": "github",
        "repo": "VeryGoodOpenSource/vgv-ai-flutter-plugin"
      }
    },
    {
      "name": "vgv-wingspan",
      "source": {
        "source": "github",
        "repo": "VeryGoodOpenSource/vgv-wingspan"
      }
    }
  ]
}
''';

      final manifest = MarketplaceManifest.fromJson(content);

      expect(manifest.plugins, hasLength(2));
      expect(manifest.plugins.first.name, 'vgv-ai-flutter-plugin');
      expect(
        manifest.plugins.first.repo,
        'VeryGoodOpenSource/vgv-ai-flutter-plugin',
      );
      expect(manifest.plugins.last.name, 'vgv-wingspan');
    });

    test('drops entries without a github repo', () {
      const content = '''
{
  "plugins": [
    {"name": "local-only", "source": {"source": "local", "path": "./x"}},
    {"name": "no-source"},
    {"source": {"source": "github", "repo": "owner/anon"}},
    {"name": "ok", "source": {"source": "github", "repo": "owner/ok"}}
  ]
}
''';

      final manifest = MarketplaceManifest.fromJson(content);

      expect(manifest.plugins, hasLength(1));
      expect(manifest.plugins.single.name, 'ok');
      expect(manifest.plugins.single.repo, 'owner/ok');
    });

    test('returns empty when plugins is missing or malformed', () {
      expect(MarketplaceManifest.fromJson('{}').plugins, isEmpty);
      expect(MarketplaceManifest.fromJson('[]').plugins, isEmpty);
      expect(
        MarketplaceManifest.fromJson('{"plugins": "nope"}').plugins,
        isEmpty,
      );
    });
  });
}
