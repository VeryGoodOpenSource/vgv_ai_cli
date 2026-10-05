import 'package:plugin_source/plugin_source.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/commands/doctor/model/model.dart';

const _plugin = PluginRef(
  name: 'wingspan',
  repo: 'acme/wingspan',
  version: '0.2.0',
  gitRef: 'v0.2.0',
);

void main() {
  group('PluginVersion', () {
    Matcher isFinding(FindingKind kind, String message) => isA<Finding>()
        .having((f) => f.kind, 'kind', kind)
        .having((f) => f.message, 'message', message);

    test('is current when the installed version is the pin', () {
      final version = PluginVersion.of(_plugin, installed: '0.2.0');

      expect(version.plugin, _plugin);
      expect(version.installed, '0.2.0');
      expect(version.status, PluginStatus.current);
      expect(version.finding, isFinding(FindingKind.current, 'wingspan 0.2.0'));
    });

    test('is older when the installed version is below the pin', () {
      final version = PluginVersion.of(_plugin, installed: '0.1.9');

      expect(version.status, PluginStatus.older);
      expect(
        version.finding,
        isFinding(FindingKind.stale, 'wingspan 0.1.9 installed, 0.2.0 pinned'),
      );
    });

    test('is newer when the installed version is above the pin', () {
      final version = PluginVersion.of(_plugin, installed: '0.10.0');

      expect(version.status, PluginStatus.newer);
      expect(
        version.finding,
        isFinding(
          FindingKind.stale,
          'wingspan 0.10.0 installed, newer than the pinned 0.2.0',
        ),
      );
    });

    test('is older when the installed version cannot be compared', () {
      final version = PluginVersion.of(_plugin, installed: 'main');

      expect(version.status, PluginStatus.older);
      expect(
        version.finding,
        isFinding(FindingKind.stale, 'wingspan main installed, 0.2.0 pinned'),
      );
    });

    test('is unrecorded when the manifest records no version', () {
      final version = PluginVersion.of(_plugin, installed: null);

      expect(version.status, PluginStatus.unrecorded);
      expect(
        version.finding,
        isFinding(FindingKind.stale, 'wingspan not recorded, 0.2.0 pinned'),
      );
    });
  });
}
