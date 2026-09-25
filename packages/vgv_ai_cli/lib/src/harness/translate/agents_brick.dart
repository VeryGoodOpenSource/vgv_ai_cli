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
  /// Renders every file [vars] select, keyed by its path in the brick.
  Future<Map<String, String>> render(Map<String, dynamic> vars) async {
    final generator = MasonGenerator(
      agentsBundle.name,
      agentsBundle.description,
      files: [
        for (final file in agentsBundle.files)
          TemplateFile.fromBytes(file.path, base64.decode(file.data)),
      ],
    );
    final target = _MemoryTarget();
    await generator.generate(target, vars: vars);
    return target.files;
  }
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
