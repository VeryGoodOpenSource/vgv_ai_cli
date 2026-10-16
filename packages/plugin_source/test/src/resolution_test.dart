import 'package:plugin_source/src/plugin_ref.dart';
import 'package:plugin_source/src/resolution.dart';
import 'package:test/test.dart';

void main() {
  group('UnavailablePlugin', () {
    test('single wraps one reason', () {
      expect(UnavailablePlugin.single('nope').reasons, ['nope']);
    });

    test('carries every reason in order', () {
      expect(const UnavailablePlugin(['a', 'b']).reasons, ['a', 'b']);
    });
  });

  group('PluginRef', () {
    test('keeps the cache version and the git ref distinct', () {
      for (final ref in vgvPlugins) {
        expect(ref.gitRef, isNot(ref.version));
        expect(ref.gitRef, startsWith('v'));
      }
    });

    test('toString uses the declared version', () {
      expect(vgvPlugins.first.toString(), 'vgv-wingspan@0.0.5');
    });
  });
}
