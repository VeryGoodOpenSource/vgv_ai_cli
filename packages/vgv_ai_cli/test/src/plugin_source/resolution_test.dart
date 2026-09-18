import 'package:file/memory.dart';
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/plugin_source/plugin_ref.dart';
import 'package:vgv_ai_cli/src/plugin_source/resolution.dart';

void main() {
  group('resolveHome', () {
    late MemoryFileSystem fileSystem;

    setUp(() => fileSystem = MemoryFileSystem());

    test('prefers USERPROFILE on Windows', () {
      final home = resolveHome(
        fileSystem: fileSystem,
        environment: const {
          'USERPROFILE': r'C:\Users\dev',
          'HOME': '/home/dev',
        },
        isWindows: true,
      );

      expect(home.path, r'C:\Users\dev');
    });

    test('falls back to HOME on Windows', () {
      final home = resolveHome(
        fileSystem: fileSystem,
        environment: const {'HOME': '/home/dev'},
        isWindows: true,
      );

      expect(home.path, '/home/dev');
    });

    test('prefers HOME elsewhere', () {
      final home = resolveHome(
        fileSystem: fileSystem,
        environment: const {
          'HOME': '/home/dev',
          'USERPROFILE': r'C:\Users\dev',
        },
        isWindows: false,
      );

      expect(home.path, '/home/dev');
    });

    test('falls back to USERPROFILE elsewhere', () {
      final home = resolveHome(
        fileSystem: fileSystem,
        environment: const {'USERPROFILE': r'C:\Users\dev'},
        isWindows: false,
      );

      expect(home.path, r'C:\Users\dev');
    });

    test('treats an empty value as unset', () {
      final home = resolveHome(
        fileSystem: fileSystem,
        environment: const {'HOME': '', 'USERPROFILE': '/fallback'},
        isWindows: false,
      );

      expect(home.path, '/fallback');
    });

    test('throws when neither is set', () {
      expect(
        () => resolveHome(
          fileSystem: fileSystem,
          environment: const {},
          isWindows: false,
        ),
        throwsA(isA<MissingHomeException>()),
      );
    });

    test('MissingHomeException names both variables', () {
      expect(
        const MissingHomeException().toString(),
        allOf(contains('HOME'), contains('USERPROFILE')),
      );
    });
  });

  group('UnavailablePlugin', () {
    test('single wraps one reason', () {
      expect(UnavailablePlugin.single('nope').reasons, ['nope']);
    });

    test('carries every reason in order', () {
      expect(const UnavailablePlugin(['a', 'b']).reasons, ['a', 'b']);
    });
  });

  group('PluginResolutionException', () {
    test('names the plugin and every reason in order', () {
      const ref = PluginRef(
        name: 'vgv-wingspan',
        repo: 'VeryGoodOpenSource/vgv-wingspan',
        version: '0.0.5',
        gitRef: 'v0.0.5',
      );

      final message = const PluginResolutionException(ref, [
        'cache missed',
        'clone failed',
      ]).toString();

      expect(message, contains('vgv-wingspan@0.0.5'));
      expect(
        message.indexOf('cache missed'),
        lessThan(message.indexOf('clone failed')),
      );
    });
  });

  group('PluginParseException', () {
    test('is not a FormatException', () {
      // The command runner catches FormatException and renders it as a CLI
      // usage error. YamlException and jsonDecode both throw FormatException,
      // so a corrupt plugin file must not be one.
      expect(
        const PluginParseException('a.md', 'bad'),
        isNot(isA<FormatException>()),
      );
    });

    test('names the file and the parser message', () {
      expect(
        const PluginParseException('skills/a/SKILL.md', 'no fence').toString(),
        allOf(contains('skills/a/SKILL.md'), contains('no fence')),
      );
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
