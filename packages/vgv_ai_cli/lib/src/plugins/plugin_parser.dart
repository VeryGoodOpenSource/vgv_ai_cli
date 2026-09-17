import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/plugins/frontmatter.dart';
import 'package:vgv_ai_cli/src/plugins/models/parsed_plugin.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_agent.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_manifest.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_metadata.dart';
import 'package:vgv_ai_cli/src/plugins/models/plugin_source.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_exception.dart';

/// One plugin directory paired with where it came from.
typedef PluginInput = ({Directory directory, PluginSource source});

const _knownMetadataKeys = {
  'name',
  'version',
  'description',
  'author',
  'homepage',
  'repository',
  'license',
  'keywords',
};

const _knownAgentKeys = {
  'name',
  'description',
  'model',
  'effort',
  'skills',
  'tools',
};

/// {@template plugin_parser}
/// Reads Claude plugin directories into a [PluginManifest].
///
/// Reads the filesystem and never the network, so it is fully testable against
/// a committed fixture tree. Parsing is lossless: any frontmatter or
/// `plugin.json` key this parser does not name is preserved under `extra`.
/// {@endtemplate}
class PluginParser {
  /// {@macro plugin_parser}
  const new();

  /// Parses every input into one manifest.
  PluginManifest parseAll(Iterable<PluginInput> inputs) => PluginManifest(
    plugins: [
      for (final input in inputs)
        parsePlugin(input.directory, source: input.source),
    ],
  );

  /// Parses a single plugin directory.
  ///
  /// [source] is supplied by the caller rather than discovered, so a fetch
  /// layer can fill in a resolved commit without changing this shape.
  ParsedPlugin parsePlugin(
    Directory directory, {
    required PluginSource source,
  }) {
    return ParsedPlugin(
      source: source,
      metadata: _readMetadata(directory),
      agents: _readAgents(directory),
    );
  }

  PluginMetadata _readMetadata(Directory directory) {
    final file = File(p.join(directory.path, '.claude-plugin', 'plugin.json'));
    if (!file.existsSync()) throw MissingPluginMetadata(file.path);

    final Object? decoded;
    try {
      decoded = jsonDecode(_readAsString(file));
    } on FormatException catch (error) {
      throw InvalidPluginMetadata(file.path, error.message);
    }

    if (decoded is! Map<String, dynamic>) {
      throw InvalidPluginMetadata(file.path, 'expected a JSON object');
    }

    final name = decoded['name'];
    if (name is! String || name.isEmpty) {
      throw InvalidPluginMetadata(file.path, 'missing required "name"');
    }

    return PluginMetadata(
      name: name,
      version: _asString(decoded['version']),
      description: _asString(decoded['description']),
      author: toSortedJson(decoded['author']),
      homepage: _asString(decoded['homepage']),
      repository: _asString(decoded['repository']),
      license: _asString(decoded['license']),
      keywords: PluginAgent.normalizeStringList(decoded['keywords']),
      extra: _extraKeys(decoded, _knownMetadataKeys),
    );
  }

  List<PluginAgent> _readAgents(Directory directory) {
    final agentsDirectory = Directory(p.join(directory.path, 'agents'));
    if (!agentsDirectory.existsSync()) {
      throw NoAgentsFound(agentsDirectory.path);
    }

    // Sorted so that a duplicate-id error names the same two files on every
    // platform. Directory traversal order is not stable.
    final files =
        agentsDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.extension(file.path).toLowerCase() == '.md')
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) throw NoAgentsFound(agentsDirectory.path);

    return [
      for (final entry in resolveAgentIds(files, agentsDirectory).entries)
        _readAgent(entry.value, entry.key),
    ];
  }

  /// Maps each file to its agent id, rejecting collisions.
  ///
  /// The id is the path under `agents/` without its extension, always joined
  /// with forward slashes so Windows does not emit a different manifest.
  ///
  /// Pure string work over [File] paths, so a collision is testable without a
  /// filesystem that can actually hold both files. On a case-insensitive
  /// filesystem `a.md` and `a.MD` cannot coexist, but on a case-sensitive one
  /// they collapse to the same id.
  static Map<String, File> resolveAgentIds(
    List<File> files,
    Directory agentsDirectory,
  ) {
    final byId = <String, File>{};
    for (final file in files) {
      final relative = p.relative(file.path, from: agentsDirectory.path);
      final id = p.split(p.withoutExtension(relative)).join('/');
      final previous = byId[id];
      if (previous != null) {
        throw DuplicateAgentId(
          file.path,
          'id "$id" was already produced by ${previous.path}',
        );
      }
      byId[id] = file;
    }
    return byId;
  }

  PluginAgent _readAgent(File file, String id) {
    final ParsedDocument document;
    try {
      document = splitFrontmatter(_readAsString(file));
      // YamlException extends FormatException, so malformed YAML and a
      // non-mapping frontmatter both land here.
    } on FormatException catch (error) {
      throw InvalidAgent(file.path, error.message);
    }

    final data = document.data;
    final name = data['name'];
    if (name is! String || name.isEmpty) {
      throw InvalidAgent(file.path, 'missing required "name" in frontmatter');
    }

    return PluginAgent(
      id: id,
      name: name,
      description: _asString(data['description']) ?? '',
      model: _asString(data['model']),
      effort: _asString(data['effort']),
      body: document.body,
      skills: PluginAgent.normalizeStringList(data['skills']),
      tools: PluginAgent.normalizeStringList(data['tools']),
      extra: _extraKeys(data, _knownAgentKeys),
    );
  }

  /// Every key of [source] that [known] does not name, preserving the sorted
  /// order [toSortedJson] established.
  Map<String, dynamic> _extraKeys(
    Map<String, dynamic> source,
    Set<String> known,
  ) => {
    for (final entry in source.entries)
      if (!known.contains(entry.key)) entry.key: toSortedJson(entry.value),
  };

  String _readAsString(File file) {
    try {
      return file.readAsStringSync();
    } on FileSystemException catch (error) {
      // Covers both IO failures and a bad encoding: dart:io wraps a UTF-8
      // decoding error in a FileSystemException rather than letting the
      // FormatException escape.
      throw UnreadableFile(file.path, error.message);
    }
  }

  String? _asString(Object? value) => value?.toString();
}
