import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_plugins/src/plugin_ref.dart';
import 'package:vgv_ai_plugins/src/resolution.dart';

void main() {
  group(UnavailablePlugin, () {
    test('single wraps one reason', () {
      expect(UnavailablePlugin.single('nope').reasons, ['nope']);
    });

    test('carries every reason in order', () {
      expect(const UnavailablePlugin(['a', 'b']).reasons, ['a', 'b']);
    });
  });

  group(PluginRef, () {
    test('keeps the cache version and the git ref distinct', () {
      for (final ref in vgvPlugins) {
        expect(ref.gitRef, isNot(ref.version));
        expect(ref.gitRef, startsWith('v'));
      }
    });

    test('pins every path as a relative folder inside its repo', () {
      for (final path in vgvPlugins.map((ref) => ref.path).nonNulls) {
        expect(p.posix.isRelative(path), isTrue, reason: path);
        expect(p.posix.normalize(path), path);
        expect(p.posix.split(path), isNot(contains('..')));
      }
    });

    test('toString uses the declared version', () {
      const ref = PluginRef(
        name: 'vgv-wingspan',
        repo: 'VeryGoodOpenSource/vgv-wingspan',
        version: '0.0.5',
        gitRef: 'v0.0.5',
      );

      expect(ref.toString(), 'vgv-wingspan@0.0.5');
    });
  });
}
