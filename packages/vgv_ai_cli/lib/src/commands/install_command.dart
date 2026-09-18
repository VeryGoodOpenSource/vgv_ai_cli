import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:vgv_ai_cli/src/generation/generation.dart';
import 'package:vgv_ai_cli/src/install/installer.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_fetcher.dart';
import 'package:vgv_ai_cli/src/plugins/plugin_resolver.dart';

/// The harness flags the command exposes, in declaration order.
const _harnessFlags = ['claude', 'gemini', 'codex', 'opencode', 'pi'];

/// {@template install_command}
///
/// `vgv_ai install`
/// Resolves the VGV Claude plugins and installs their MCP servers, skills, and
/// agents into the selected harnesses' configuration.
/// {@endtemplate}
class InstallCommand extends Command<int> {
  /// {@macro install_command}
  ///
  /// The fetcher, home, and environment are injectable so tests exercise the
  /// full pipeline against local fixtures and a temporary home; production runs
  /// leave them null and resolve the real values.
  new({required this._logger, this._fetcher, this._home, this._environment}) {
    argParser
      ..addFlag('claude', negatable: false, help: 'Configure Claude Code.')
      ..addFlag('gemini', negatable: false, help: 'Configure Gemini CLI.')
      ..addFlag('codex', negatable: false, help: 'Configure Codex.')
      ..addFlag('opencode', negatable: false, help: 'Configure OpenCode.')
      ..addFlag('pi', negatable: false, help: 'Configure pi.')
      ..addFlag(
        'all',
        negatable: false,
        help: 'Configure every supported harness.',
      )
      ..addOption(
        'skills-root',
        help: 'Directory skills are materialized into.',
        defaultsTo: '~/.agents/skills',
      )
      ..addFlag(
        'update',
        negatable: false,
        help:
            'Refresh plugins to their latest commit instead of the '
            'commit pinned in skills-lock.json.',
      );
  }

  @override
  String get description =>
      'Install VGV agent configuration into the selected harnesses.';

  @override
  String get name => 'install';

  final Logger _logger;
  final PluginFetcher? _fetcher;
  final Directory? _home;
  final Map<String, String>? _environment;

  @override
  Future<int> run() async {
    final results = argResults!;
    final selectAll = results['all'] == true;
    final harnesses = HarnessSelection(
      claude: selectAll || results['claude'] == true,
      gemini: selectAll || results['gemini'] == true,
      codex: selectAll || results['codex'] == true,
      opencode: selectAll || results['opencode'] == true,
      pi: selectAll || results['pi'] == true,
    );

    if (harnesses.isEmpty) {
      _logger.err(
        'Select at least one harness: '
        '${_harnessFlags.map((f) => '--$f').join(', ')}, or --all.',
      );
      return ExitCode.usage.code;
    }

    final progress = _logger.progress('Resolving VGV plugins');
    try {
      await _installer().install(
        harnesses: harnesses,
        skillsRoot: results['skills-root'] as String,
        update: results['update'] == true,
      );
      progress.complete('Installed VGV agent configuration.');
      return ExitCode.success.code;
    } on Exception catch (error) {
      progress.fail();
      _logger.err('$error');
      return ExitCode.software.code;
    }
  }

  Installer _installer() {
    final home = _home ?? _resolveHome();
    final fetcher =
        _fetcher ??
        GitPluginFetcher(
          workingDirectory: Directory(
            p.join(home.path, '.cache', 'vgv_ai', 'plugins'),
          )..createSync(recursive: true),
        );
    return Installer(
      resolver: PluginResolver(fetcher: fetcher),
      home: home,
    );
  }

  Directory _resolveHome() {
    final env = _environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home == null || home.isEmpty) throw const _HomeNotFound();
    return Directory(home);
  }
}

class _HomeNotFound implements Exception {
  const new();

  @override
  String toString() =>
      'Could not determine your home directory from HOME or USERPROFILE.';
}
