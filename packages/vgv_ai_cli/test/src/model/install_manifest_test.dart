import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vgv_ai_cli/src/model/model.dart';

void main() {
  /// The hex SHA-256 the manifest records for [text].
  String hashText(String text) => sha256.convert(utf8.encode(text)).toString();

  const home = '/home/dev';
  const owned = OwnedFile(
    path: '/home/dev/.agents/skills/a/SKILL.md',
    owner: null,
    sha256: 'abc',
  );
  const merged = MergedDocument(
    path: '/home/dev/.codex/config.toml',
    owner: Harness.codex,
    format: DocumentFormat.toml,
    contribution: Contribution({
      'mcp_servers': {
        'dart': {'command': 'dart'},
      },
    }),
  );
  const sections = MarkdownSections(
    path: '/home/dev/.gemini/AGENTS.md',
    owner: Harness.gemini,
    sections: {'instructions': 'def'},
  );

  String encodeEntries(List<Object?> entries) =>
      jsonEncode({'version': InstallManifest.version, 'entries': entries});

  /// [entry] as it is written to disk, with its path relative to [home].
  Map<String, Object?> onDisk(ManifestEntry entry) => {
    ...entry.toJson(),
    'path': p.relative(entry.path, from: home),
  };

  group(InstallManifest, () {
    test('round trips every kind of entry, and the plugin versions', () {
      final manifest = InstallManifest(
        const [owned, merged, sections],
        const {
          Harness.claude: {'vgv-wingspan': '0.0.5'},
          Harness.codex: {'vgv-ai-flutter-plugin': '0.0.6'},
        },
      );

      final decoded = InstallManifest.decode(
        manifest.encode(home: home),
        home: home,
      )!;

      expect(decoded, manifest);
      expect(decoded.entries.map((e) => e.mode), [
        ChangeMode.own,
        ChangeMode.mergeToml,
        ChangeMode.mergeMarkdown,
      ]);
      expect(
        decoded[merged.path],
        isA<MergedDocument>().having(
          (e) => e.format,
          'format',
          DocumentFormat.toml,
        ),
      );
      expect(
        decoded[sections.path],
        isA<MarkdownSections>().having(
          (e) => e.sections,
          'sections',
          sections.sections,
        ),
      );
      expect(
        decoded[owned.path],
        isA<OwnedFile>().having((e) => e.sha256, 'sha256', 'abc'),
      );
      expect(decoded.plugins, {
        Harness.claude: {'vgv-wingspan': '0.0.5'},
        Harness.codex: {'vgv-ai-flutter-plugin': '0.0.6'},
      });
    });

    test('encodes the version, plugins, owners and modes by name', () {
      final json = jsonDecode(
        InstallManifest(
          const [owned, merged],
          const {
            Harness.codex: {'vgv-wingspan': '0.0.5'},
          },
        ).encode(home: home),
      ) as Map<String, dynamic>;

      expect(json['version'], 3);
      expect(json['plugins'], {
        'codex': {'vgv-wingspan': '0.0.5'},
      });
      expect(json['entries'], [
        {
          'path': '.agents/skills/a/SKILL.md',
          'owner': null,
          'mode': 'own',
          'sha256': 'abc',
        },
        {
          'path': '.codex/config.toml',
          'owner': 'codex',
          'mode': 'mergeToml',
          'contribution': merged.contribution.toJson(),
        },
      ]);
    });

    test('is empty when malformed', () {
      InstallManifest? decode(String source) =>
          InstallManifest.decode(source, home: home);

      expect(decode('{ not json')!.entries, isEmpty);
      expect(decode('[]')!.entries, isEmpty);
      expect(
        decode(jsonEncode({'version': InstallManifest.version}))!.entries,
        isEmpty,
      );
      expect(
        decode(jsonEncode({owned.path: 'hash'}))!.entries,
        isEmpty,
        reason: 'the flat format before version 1 never shipped',
      );
    });

    test('has no plugin versions when they are missing or malformed', () {
      InstallManifest decode(Object? plugins) => InstallManifest.decode(
        jsonEncode({
          'version': InstallManifest.version,
          'plugins': plugins,
          'entries': <Object>[],
        }),
        home: home,
      )!;

      expect(decode(null).plugins, isEmpty);
      expect(decode(['vgv-wingspan']).plugins, isEmpty);
      expect(decode({'codex': 'vgv-wingspan'}).plugins, isEmpty);
      expect(
        decode({
          'nope': {'vgv-wingspan': '0.0.5'},
        }).plugins,
        isEmpty,
      );
      expect(
        decode({
          'codex': {'vgv-wingspan': 5, 'vgv-ai-flutter-plugin': '0.0.5'},
        }).plugins,
        {
          Harness.codex: {'vgv-ai-flutter-plugin': '0.0.5'},
        },
      );
    });

    test('is null when a newer version wrote it', () {
      expect(
        InstallManifest.decode(
          jsonEncode({
            'version': InstallManifest.version + 1,
            'entries': <Object>[],
          }),
          home: home,
        ),
        isNull,
      );
    });

    test('is empty for a version it never wrote', () {
      expect(
        InstallManifest.decode(jsonEncode({'version': 0}), home: home)!.entries,
        isEmpty,
      );
    });

    test('is empty for the version before this one', () {
      final manifest = InstallManifest.decode(
        jsonEncode({
          'version': InstallManifest.version - 1,
          'entries': [onDisk(owned)],
          'plugins': {'vgv-wingspan': '0.0.5'},
        }),
        home: home,
      )!;

      expect(manifest.entries, isEmpty);
      expect(manifest.plugins, isEmpty);
    });

    test('skips entries it does not understand', () {
      final manifest = InstallManifest.decode(
        encodeEntries([
          onDisk(owned),
          'not an entry',
          {'path': 'a', 'owner': 'cursor', 'mode': 'own', 'sha256': 'x'},
          {'path': 'b', 'owner': null, 'mode': 'own'},
          {'path': 'c', 'owner': null, 'mode': 'mergeJson'},
          {'path': 'd', 'owner': null, 'mode': 'mergeMarkdown'},
          {'path': 'e', 'owner': null, 'mode': 'somethingElse'},
          {
            'path': 'f',
            'owner': null,
            'mode': 'own',
            'contribution': <String, Object>{},
          },
        ]),
        home: home,
      )!;

      expect(manifest.entries.map((e) => e.path), [owned.path]);
    });

    test('resolves paths against home, and skips any that leave it', () {
      Map<String, Object?> at(String path) => {...onDisk(owned), 'path': path};

      final manifest = InstallManifest.decode(
        encodeEntries([
          at('.codex/../.agents/skills/a/SKILL.md'),
          at('/etc/passwd'),
          at('../other/.bashrc'),
          at('.'),
        ]),
        home: home,
      )!;

      expect(manifest.entries.map((e) => e.path), [owned.path]);
    });

    test('drops a section whose hash is not a string', () {
      final manifest = InstallManifest.decode(
        encodeEntries([
          {
            ...onDisk(sections),
            'sections': {'instructions': 'def', 'odd': 1},
          },
        ]),
        home: home,
      )!;

      expect(
        manifest[sections.path],
        isA<MarkdownSections>().having((e) => e.sections, 'sections', {
          'instructions': 'def',
        }),
      );
    });

    test('lists the entries of one owner, null being the shared skills', () {
      final manifest = InstallManifest(const [owned, merged, sections]);

      expect(manifest.entriesFor(null), [owned]);
      expect(manifest.entriesFor(Harness.codex), [merged]);
      expect(manifest.entriesFor(Harness.pi), isEmpty);
    });

    test('records an entry in place of the one for its path', () {
      const updated = OwnedFile(path: '/x', owner: null, sha256: 'new');
      final manifest = InstallManifest(
        const [OwnedFile(path: '/x', owner: null, sha256: 'old'), merged],
        const {
          Harness.codex: {'vgv-wingspan': '0.0.5'},
        },
      ).record(updated);

      expect(manifest.entries, [updated, merged]);
      expect(manifest.plugins, {
        Harness.codex: {'vgv-wingspan': '0.0.5'},
      });
    });

    test('drops the entries for the given paths', () {
      final manifest = InstallManifest(
        const [owned, merged, sections],
        const {
          Harness.codex: {'vgv-wingspan': '0.0.5'},
        },
      ).without([owned.path, sections.path]);

      expect(manifest.entries, [merged]);
      expect(manifest.plugins, {
        Harness.codex: {'vgv-wingspan': '0.0.5'},
      });
    });

    test('replaces the plugin versions, keeping the entries', () {
      final manifest =
          InstallManifest(
            const [owned],
            const {
              Harness.codex: {'vgv-wingspan': '0.0.4'},
            },
          ).withPlugins(const {
            Harness.codex: {'vgv-wingspan': '0.0.5'},
          });

      expect(manifest.entries, [owned]);
      expect(manifest.plugins, {
        Harness.codex: {'vgv-wingspan': '0.0.5'},
      });
    });

    test('equals a manifest with the same entries, in the same order', () {
      expect(
        InstallManifest(const [owned, merged]),
        InstallManifest(const [owned, merged]),
      );
      expect(
        InstallManifest(const [owned, merged]),
        isNot(InstallManifest(const [merged, owned])),
      );
      expect(
        InstallManifest(const [owned]),
        isNot(
          InstallManifest([
            OwnedFile(path: owned.path, owner: null, sha256: 'other'),
          ]),
        ),
      );
      expect(
        InstallManifest(
          const [owned],
          const {
            Harness.codex: {'vgv-wingspan': '0.0.5'},
          },
        ),
        isNot(
          InstallManifest(
            const [owned],
            const {
              Harness.codex: {'vgv-wingspan': '0.0.4'},
            },
          ),
        ),
      );
    });

    test('has no entry for a path it has not recorded', () {
      expect(InstallManifest()['/nowhere'], isNull);
    });

    test('looks an entry up by its kind', () {
      final manifest = InstallManifest(const [owned, merged]);

      expect(manifest.entryOf<OwnedFile>(owned.path), owned);
      expect(manifest.entryOf<MergedDocument>(owned.path), isNull);
      expect(manifest.entryOf<OwnedFile>('/nowhere'), isNull);
    });
  });

  group(OwnedFile, () {
    test('records the hash of what VGV wrote', () {
      final file = OwnedFile.of(
        path: owned.path,
        owner: null,
        bytes: utf8.encode('abc'),
      );

      expect(file.sha256, hashText('abc'));
      expect(file.isUntouched(utf8.encode('abc')), isTrue);
    });

    test('is untouched only while it hashes to what VGV wrote', () {
      final file = OwnedFile(
        path: owned.path,
        owner: null,
        sha256: hashText('abc'),
      );

      expect(file.isUntouched(utf8.encode('abc')), isTrue);
      expect(file.isUntouched(utf8.encode('abd')), isFalse);
    });
  });

  group(MarkdownSections, () {
    test('records a section beside the ones it has', () {
      final file = sections.recording('b', '# B');

      expect(file.path, sections.path);
      expect(file.owner, sections.owner);
      expect(file.sections, {'instructions': 'def', 'b': hashText('# B')});
      expect(file.isUntouched('b', '# B'), isTrue);
    });

    test('is untouched only while a section hashes to what VGV wrote', () {
      final file = MarkdownSections(
        path: sections.path,
        owner: Harness.gemini,
        sections: {'instructions': hashText('# VGV')},
      );

      expect(file.isUntouched('instructions', '# VGV'), isTrue);
      expect(file.isUntouched('instructions', '# Mine'), isFalse);
      expect(file.isUntouched('other', '# VGV'), isFalse);
    });
  });
}
