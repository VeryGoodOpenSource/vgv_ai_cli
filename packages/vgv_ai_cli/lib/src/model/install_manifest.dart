import 'dart:convert';

import 'package:ack/ack.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/model/contribution.dart';
import 'package:vgv_ai_cli/src/model/harness.dart';
import 'package:vgv_ai_cli/src/model/planned_change.dart';

/// {@template manifest_entry}
/// What VGV wrote to one file, and so what `doctor` checks and `uninstall`
/// takes back.
/// {@endtemplate}
sealed class const ManifestEntry({
  /// The file, as an absolute path.
  required final String path,

  /// The harness the file configures, or null for the shared skills.
  required final Harness? owner,
}) extends Equatable {
  /// How [path] was written.
  ChangeMode get mode;

  Map<String, Object?> toJson() => {
    'path': path,
    'owner': owner?.name,
    'mode': mode.name,
    ..._fields,
  };

  Map<String, Object?> get _fields;

  @override
  List<Object?> get props => [path, owner, mode, _fields];

  /// Every entry shape this version writes, by its mode, decoding to the
  /// entry, with its path resolved against [home].
  ///
  /// The mode is read back by the same name [toJson] writes it with, so the
  /// two cannot drift apart. An entry whose owner or mode is unknown, whose
  /// fields are missing, or whose path is absolute or leads out of [home],
  /// fails to parse.
  static DiscriminatedObjectSchema<ManifestEntry> schema({
    required String home,
  }) {
    ObjectSchema shape(
      ChangeMode mode,
      Map<String, AckSchema<Object, Object>> fields,
    ) => Ack.object({
      'path': Ack.string()
          .refine((path) => !p.isAbsolute(path), message: 'is absolute')
          .transform((path) => p.normalize(p.join(home, path)))
          .refine((path) => p.isWithin(home, path), message: 'leaves home'),
      'owner': Ack.enumValues(Harness.values).nullable(),
      'mode': Ack.literal(mode.name),
      ...fields,
    }, additionalProperties: true);

    return Ack.discriminated(
      discriminatorKey: 'mode',
      schemas: {
        ChangeMode.own.name: shape(ChangeMode.own, {
          'sha256': Ack.string(),
        }).transform((json) => _EntryJson(json).ownedFile),
        for (final format in DocumentFormat.values)
          format.mode.name: shape(format.mode, {
            'contribution': Ack.map(Ack.any().nullable()),
          }).transform((json) => _EntryJson(json).mergedDocument(format)),
        ChangeMode.mergeMarkdown.name: shape(ChangeMode.mergeMarkdown, {
          // Any values, so a corrupt hash drops one section, not the entry.
          'sections': Ack.map(Ack.any().nullable()),
        }).transform((json) => _EntryJson(json).markdownSections),
      },
    );
  }
}

/// A manifest entry as [ManifestEntry.schema] has validated it.
extension type _EntryJson(Map<String, Object?> _json) {
  String get _path => _json['path']! as String;

  Harness? get _owner => _json['owner'] as Harness?;

  OwnedFile get ownedFile =>
      OwnedFile(path: _path, owner: _owner, sha256: _json['sha256']! as String);

  MergedDocument mergedDocument(DocumentFormat format) => MergedDocument(
    path: _path,
    owner: _owner,
    format: format,
    contribution: Contribution(_json['contribution']! as Map<String, Object?>),
  );

  MarkdownSections get markdownSections => MarkdownSections(
    path: _path,
    owner: _owner,
    sections: {
      for (final MapEntry(:key, :value)
          in (_json['sections']! as Map<String, Object?>).entries)
        if (value case final String hash) key: hash,
    },
  );
}

/// {@template owned_file}
/// A file VGV wrote whole. It is VGV's while it still hashes to [sha256].
/// {@endtemplate}
final class const OwnedFile({
  required super.path,
  required super.owner,

  /// The SHA-256 of what VGV last wrote.
  required final String sha256,
}) extends ManifestEntry {
  /// {@macro owned_file}
  ///
  /// Records [bytes] as what VGV wrote to [path].
  new of({
    required String path,
    required Harness? owner,
    required List<int> bytes,
  }) : this(path: path, owner: owner, sha256: _sha256(bytes));

  /// Whether [bytes] are exactly what VGV last wrote.
  bool isUntouched(List<int> bytes) => _sha256(bytes) == sha256;

  @override
  ChangeMode get mode => ChangeMode.own;

  @override
  Map<String, Object?> get _fields => {'sha256': sha256};
}

/// {@template merged_document}
/// A JSON or TOML document VGV merged keys into.
/// {@endtemplate}
final class const MergedDocument({
  required super.path,
  required super.owner,

  /// The format the document is parsed as.
  required final DocumentFormat format,

  /// The part of the document that is VGV's.
  required final Contribution contribution,
}) extends ManifestEntry {
  @override
  ChangeMode get mode => format.mode;

  @override
  Map<String, Object?> get _fields => {'contribution': contribution.toJson()};
}

/// {@template markdown_sections}
/// A markdown file VGV wrote named sections into.
/// {@endtemplate}
final class const MarkdownSections({
  required super.path,
  required super.owner,

  /// Each section's name to the SHA-256 of the body VGV last wrote there.
  required final Map<String, String> sections,
}) extends ManifestEntry {
  /// This entry with [body] recorded as what VGV wrote into section [name].
  MarkdownSections recording(String name, String body) => MarkdownSections(
    path: path,
    owner: owner,
    sections: {...sections, name: _hashText(body)},
  );

  /// Whether [body] is exactly what VGV last wrote into section [name].
  bool isUntouched(String name, String body) =>
      sections[name] == _hashText(body);

  @override
  ChangeMode get mode => ChangeMode.mergeMarkdown;

  @override
  Map<String, Object?> get _fields => {'sections': sections};
}

/// {@template install_manifest}
/// Everything VGV wrote under a home directory, by file, and the plugin
/// versions it was written from.
///
/// `install` writes it, and `doctor` and `uninstall` read it, so this is the
/// one place ownership is defined. It is persisted rather than recomputed
/// from the plugins: a plan cannot tell a key VGV added from one the user
/// already had, and it forgets what an older plugin version wrote.
///
/// Paths are absolute in memory and relative to the home directory on disk,
/// so the manifest survives the home directory moving, and never names a
/// file outside it.
/// {@endtemplate}
class InstallManifest extends Equatable {
  /// {@macro install_manifest}
  new([Iterable<ManifestEntry> entries = const [], this.plugins = const {}])
    : _entries = {for (final entry in entries) entry.path: entry};

  /// Decodes [source], with its paths resolved against [home], keeping
  /// every entry it understands, or returns null when a newer version of
  /// vgv_ai wrote it.
  ///
  /// A malformed manifest is empty: an unrecorded file is the user's, which
  /// is the safe way to be wrong. So is an entry whose path is absolute or
  /// leads out of [home]. A version 1 manifest is read as one that records
  /// no plugin versions. One from a newer version is null, because writing
  /// over it would lose everything it records.
  static InstallManifest? decode(String source, {required String home}) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return InstallManifest();
    }

    final entry = ManifestEntry.schema(home: home);
    return switch (json) {
      {
        'version': 1 || InstallManifest.version,
        'entries': final List<dynamic> list,
      } =>
        InstallManifest(
          [for (final item in list) ?entry.safeParse(item).getOrNull()],
          {
            if (json['plugins'] case final Map<String, dynamic> plugins)
              for (final MapEntry(:key, :value) in plugins.entries)
                if (value is String) key: value,
          },
        ),
      {'version': final int other} when other > version => null,
      _ => InstallManifest(),
    };
  }

  /// The format [encode] writes.
  static const version = 2;

  final Map<String, ManifestEntry> _entries;

  /// Each plugin's name to the version VGV's files were written from.
  final Map<String, String> plugins;

  /// Every entry, in the order they were recorded.
  Iterable<ManifestEntry> get entries => _entries.values;

  /// The entries [owner] owns, where null is the shared skills.
  Iterable<ManifestEntry> entriesFor(Harness? owner) {
    return entries.where((entry) => entry.owner == owner);
  }

  /// The entry for [path], or null when VGV has not recorded it.
  ManifestEntry? operator [](String path) => _entries[path];

  /// The entry for [path] when it is a [T], and null otherwise.
  T? entryOf<T extends ManifestEntry>(String path) => switch (_entries[path]) {
    final T entry => entry,
    _ => null,
  };

  /// This manifest with [entry] in place of any entry for its path.
  InstallManifest record(ManifestEntry entry) {
    return InstallManifest([..._entries.values, entry], plugins);
  }

  /// This manifest without the entries for [paths].
  InstallManifest without(Iterable<String> paths) {
    final dropped = paths.toSet();
    return InstallManifest(
      entries.where((e) => !dropped.contains(e.path)),
      plugins,
    );
  }

  /// This manifest with [plugins] as the versions it was written from.
  InstallManifest withPlugins(Map<String, String> plugins) {
    return InstallManifest(entries, plugins);
  }

  /// The manifest as the JSON [InstallManifest.decode] reads, with its
  /// paths relative to [home].
  String encode({required String home}) {
    final json = {
      'version': version,
      'plugins': plugins,
      'entries': [
        for (final entry in entries)
          {...entry.toJson(), 'path': p.relative(entry.path, from: home)},
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  @override
  List<Object?> get props => [entries.toList(), plugins];
}

/// The SHA-256 of [bytes], as hex.
String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

/// The SHA-256 of [text] as UTF-8, as hex.
String _hashText(String text) => _sha256(utf8.encode(text));
