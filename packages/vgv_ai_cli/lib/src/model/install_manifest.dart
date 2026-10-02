import 'dart:convert';

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
sealed class ManifestEntry extends Equatable {
  /// {@macro manifest_entry}
  const new({required this.path, required this.owner});

  /// The file, as an absolute path.
  final String path;

  /// The harness the file configures, or null for the shared skills.
  final Harness? owner;

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

  /// Decodes one entry, or null when it is not one this version writes.
  ///
  /// The mode is read back by the same name [toJson] writes it with, so the
  /// two cannot drift apart.
  static ManifestEntry? fromJson(Object? json) {
    if (json
        case final Map<dynamic, dynamic> entry &&
            {
              'path': final String path,
              'owner': final String? owner,
              'mode': final String mode,
            }) {
      final harness = Harness.values.asNameMap()[owner];
      if (owner != null && harness == null) return null;

      return _decode(
        entry,
        path: path,
        owner: harness,
        mode: ChangeMode.values.asNameMap()[mode],
      );
    }
    return null;
  }

  /// Decodes the fields of [json] that [mode] writes, or null when [mode] is
  /// unknown or its fields are missing.
  static ManifestEntry? _decode(
    Map<dynamic, dynamic> json, {
    required String path,
    required Harness? owner,
    required ChangeMode? mode,
  }) {
    final format = mode?.format;
    if (json case {'sha256': final String sha256} when mode == ChangeMode.own) {
      return OwnedFile(path: path, owner: owner, sha256: sha256);
    }
    if (json case {'contribution': final Map<String, dynamic> contribution}
        when format != null) {
      return MergedDocument(
        path: path,
        owner: owner,
        format: format,
        contribution: Contribution(contribution),
      );
    }
    if (json case {'sections': final Map<String, dynamic> sections}
        when mode == ChangeMode.mergeMarkdown) {
      return MarkdownSections(
        path: path,
        owner: owner,
        sections: {
          for (final MapEntry(:key, :value) in sections.entries)
            if (value is String) key: value,
        },
      );
    }
    return null;
  }
}

/// {@template owned_file}
/// A file VGV wrote whole. It is VGV's while it still hashes to [sha256].
/// {@endtemplate}
final class OwnedFile extends ManifestEntry {
  /// {@macro owned_file}
  const new({required super.path, required super.owner, required this.sha256});

  /// {@macro owned_file}
  ///
  /// Records [bytes] as what VGV wrote to [path].
  new of({
    required String path,
    required Harness? owner,
    required List<int> bytes,
  }) : this(path: path, owner: owner, sha256: _sha256(bytes));

  /// The SHA-256 of what VGV last wrote.
  final String sha256;

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
final class MergedDocument extends ManifestEntry {
  /// {@macro merged_document}
  const new({
    required super.path,
    required super.owner,
    required this.format,
    required this.contribution,
  });

  /// The format the document is parsed as.
  final DocumentFormat format;

  /// The part of the document that is VGV's.
  final Contribution contribution;

  @override
  ChangeMode get mode => format.mode;

  @override
  Map<String, Object?> get _fields => {'contribution': contribution.toJson()};
}

/// {@template markdown_sections}
/// A markdown file VGV wrote named sections into.
/// {@endtemplate}
final class MarkdownSections extends ManifestEntry {
  /// {@macro markdown_sections}
  const new({
    required super.path,
    required super.owner,
    required this.sections,
  });

  /// Each section's name to the SHA-256 of the body VGV last wrote there.
  final Map<String, String> sections;

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
  /// every entry it understands, or returns null when another version of
  /// vgv_ai wrote it.
  ///
  /// A malformed manifest is empty: an unrecorded file is the user's, which
  /// is the safe way to be wrong. So is an entry whose path is absolute or
  /// leads out of [home]. One from another version is null, because writing
  /// over it would lose everything it records.
  static InstallManifest? decode(String source, {required String home}) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return InstallManifest();
    }

    return switch (json) {
      {
        'version': InstallManifest.version,
        'entries': final List<dynamic> list,
      } =>
        InstallManifest(
          [
            for (final item in list)
              ?ManifestEntry.fromJson(_resolved(item, home: home)),
          ],
          {
            if (json['plugins'] case final Map<String, dynamic> plugins)
              for (final MapEntry(:key, :value) in plugins.entries)
                if (value is String) key: value,
          },
        ),
      {'version': final int other} when other != version => null,
      _ => InstallManifest(),
    };
  }

  /// [item] with its path resolved against [home], or null when the path
  /// is absolute or leads out of [home].
  static Object? _resolved(Object? item, {required String home}) {
    if (item is! Map<String, dynamic>) return null;

    final relative = item['path'];
    if (relative is! String || p.isAbsolute(relative)) return null;

    final path = p.normalize(p.join(home, relative));
    return p.isWithin(home, path) ? {...item, 'path': path} : null;
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
