import 'dart:convert';

import 'package:mason/mason.dart';
import 'package:vgv_ai_cli/src/templates/templates.dart';

/// {@template agents_brick}
/// Renders the `agents` brick into memory.
///
/// Nothing is generated into `$HOME` or a staging directory, so `--check`
/// stays a true dry run and the reconcile layer decides what reaches disk.
/// The generator is built straight from the bundle too, because
/// `MasonGenerator.fromBundle` unpacks it into `~/.mason-cache` and reads it
/// back. The brick has no hooks, so the bundle's files are all it needs.
/// {@endtemplate}
class const AgentsBrick() {
  /// {@macro agents_brick}
  this;

  /// Renders every file [vars] select, keyed by its path in the brick.
  Future<Map<String, String>> render(Map<String, Object?> vars) async {
    final generator = MasonGenerator(
      agentsBundle.name,
      agentsBundle.description,
      files: [
        for (final file in agentsBundle.files)
          TemplateFile.fromBytes(file.path, base64.decode(file.data)),
      ],
    );
    final target = _MemoryTarget();
    await generator.generate(target, vars: _escapedMap(vars));
    return target.files;
  }

  /// A backslash before a newline or a non-ASCII character in rendered
  /// output. Mason strips it, taking the shell line continuation in a prompt
  /// with it, so every such backslash in a value is doubled first.
  ///
  /// This mirrors `_sanitizeOutput` in mason's `lib/src/render.dart`, so
  /// recheck it whenever the mason constraint moves.
  static final _strippedBackslash = RegExp(r'\\(?=\r|\n|[^\x00-\x7F])');

  /// [value] with every string in it guarded against [_strippedBackslash].
  static Object? _escaped(Object? value) => switch (value) {
    final String text => text.replaceAll(_strippedBackslash, r'\\'),
    final Map<String, Object?> map => _escapedMap(map),
    final List<Object?> list => [for (final entry in list) _escaped(entry)],
    _ => value,
  };

  /// [map] with every string in it guarded against [_strippedBackslash].
  static Map<String, Object?> _escapedMap(Map<String, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries) key: _escaped(value),
  };
}

class _MemoryTarget implements GeneratorTarget {
  final files = <String, String>{};

  @override
  Future<GeneratedFile> createFile(
    String path,
    List<int> contents, {
    Logger? logger,
    OverwriteRule? overwriteRule,
  }) async {
    files[path] = utf8.decode(contents);
    return GeneratedFile.created(path: path);
  }
}
