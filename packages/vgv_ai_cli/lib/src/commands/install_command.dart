import 'dart:io' show stdin;

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:vgv_ai_cli/src/commands/empty_directories.dart';
import 'package:vgv_ai_cli/src/commands/harness_selection.dart';
import 'package:vgv_ai_cli/src/commands/reporting_manifest_store.dart';
import 'package:vgv_ai_cli/src/commands/user_home.dart';
import 'package:vgv_ai_cli/src/detect/detect.dart';
import 'package:vgv_ai_cli/src/document/document.dart';
import 'package:vgv_ai_cli/src/manifest/manifest.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/reconcile/reconcile.dart';
import 'package:vgv_ai_cli/src/resolve/resolve.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:vgv_ai_plugins/vgv_ai_plugins.dart';

/// {@template install_command}
/// Configures the Very Good AI tooling for the detected coding-agent harnesses.
///
/// * `--check` prints the changes without writing them. It still asks which
///   plugins to install in a terminal, so it shows what a real run would do.
/// * `--force` takes VGV's values where they conflict with the user's.
/// * `--only` configures the named harnesses, detected or not.
/// * `--no-<harness>` skips one detected harness. It cannot be combined with
///   `--only`, which already names the set.
/// * `--plugin` installs just the named VGV plugins. Without it, a run in a
///   terminal asks which plugins to install, and any other run installs
///   every pinned one.
/// * `--refresh` reinstalls the harnesses and plugins the manifest records,
///   at the pinned versions, without asking. `update` runs it.
/// * `--project [<dir>]` installs into the project at `dir`, or the working
///   directory, for every harness rather than the detected ones, since the
///   project is shared with whoever clones it. `--only` and `--no-<harness>`
///   narrow the set as usual. A rerun that covers every harness and plugin
///   the project records also takes back what VGV wrote before and no
///   longer writes, such as a plugin copy from an older tag.
///
/// A file an earlier version wrote to a folder this version no longer uses
/// is taken back, as `uninstall` would, so the harness does not load both
/// copies. It is kept when its replacement could not be written.
/// {@endtemplate}
class InstallCommand({
  required final Logger _logger,
  final Directory? _home,
  final Map<String, String>? _environment,
  final PluginResolver _resolver = const PluginResolver(),
  final HarnessDetector _detector = const HarnessDetector(),
  final Translator _translator = const Translator(),
  final Reconciler _reconciler = const Reconciler(),
  final ManifestAuditor _auditor = const ManifestAuditor(),
  bool? hasTerminal,
  Directory? workingDirectory,
}) extends Command<int> with HarnessSelection {
  /// {@macro install_command}
  this {
    argParser
      ..addFlag(
        'check',
        help: 'Print what would be written without writing anything.',
        negatable: false,
      )
      ..addFlag(
        'force',
        help:
            'Also overwrite your values that conflict with the ones install '
            'writes.',
        negatable: false,
      )
      ..addMultiOption(
        'plugin',
        help: 'Install just these VGV plugins instead of choosing them.',
        allowed: [for (final plugin in vgvPlugins) plugin.name],
      )
      ..addFlag(
        projectFlag,
        help:
            'Install into the project at the directory given after the '
            'options, or the working directory, for every harness.',
        negatable: false,
      )
      ..addFlag(
        refreshFlag,
        help:
            'Reinstall the harnesses and plugins a previous install wrote, '
            'at the pinned versions.',
        negatable: false,
        hide: true,
      );
    addHarnessOptions('Configure the Very Good AI tooling for');
  }

  /// The name the CLI registers `install` under, so other code can name it
  /// without constructing one.
  static const String commandName = 'install';

  /// The flag `update` passes to reinstall what a previous install wrote.
  /// Older versions of `update` pass it too, so it must keep its name.
  static const String refreshFlag = 'refresh';

  /// The flag that installs into a project instead of the user's home.
  static const String projectFlag = 'project';

  /// Whether stdin is a terminal, so install can ask which plugins to install.
  final bool _hasTerminal = hasTerminal ?? stdin.hasTerminal;

  /// The directory a relative `--project` directory is resolved against.
  final Directory _workingDirectory =
      workingDirectory ?? const LocalFileSystem().currentDirectory;

  /// The outcomes that leave a file with VGV's contributions in it.
  static const Set<ChangeOutcome> _wrote = {
    ChangeOutcome.created,
    ChangeOutcome.updated,
    ChangeOutcome.partial,
  };

  /// The outcomes that leave a file holding everything VGV contributes, or
  /// all of it but the user's values, so the copy it replaces can go.
  static const Set<ChangeOutcome> _replaced = {
    ..._wrote,
    ChangeOutcome.unchanged,
  };

  /// The outcomes where a value the user set won over VGV's.
  static const Set<ChangeOutcome> _keptUserValues = {
    ChangeOutcome.partial,
    ChangeOutcome.skipped,
  };

  @override
  String get description =>
      'Configure the Very Good AI tooling for your coding agents.';

  @override
  String get name => commandName;

  @override
  String get invocation => '${super.invocation} [--project [<dir>]]';

  /// The directory install configures, or null when it cannot be found.
  Directory? get home => commandHome(_home, _environment);

  @override
  Future<int> run() async {
    final force = argResults!['force'] == true;
    final dryRun = argResults!['check'] == true;
    final refresh = argResults![refreshFlag] == true;
    if (refresh) _rejectSelectionWithRefresh();

    // Falling back to the working directory would scatter harness config
    // wherever install happened to run, so a missing home is fatal.
    final home = this.home;
    if (home == null) {
      _logger.err(
        'Could not find your home directory. Set HOME and run install again.',
      );
      return ExitCode.config.code;
    }
    final scope = _scope(home);

    // Loaded before anything is resolved, since a manifest this version
    // cannot read means nothing can be installed.
    final store = ReportingManifestStore(
      ManifestStore(scope.root),
      _logger,
      nothingDone: 'Installed nothing',
      done: 'written',
      retry: 'install',
    );
    final manifest = store.load();
    if (manifest == null) return ExitCode.ioError.code;

    final selected = refresh
        ? manifest.plugins.keys.toSet()
        : await _select(scope);
    if (selected.isEmpty) {
      _logger.err(refresh ? _nothingToRefresh : _noHarnessSelected);
      return ExitCode.usage.code;
    }

    final plugins = refresh
        ? _recordedPlugins(manifest, selected)
        : _selectPlugins(manifest, selected);
    if (plugins.isEmpty) {
      _logger.err(
        'No plugin selected. Choose at least one, or pass --plugin to name '
        'one explicitly.',
      );
      return ExitCode.usage.code;
    }

    final resolved = await _resolveAssets(home, plugins, scope: scope);
    if (resolved == null) return ExitCode.unavailable.code;

    final plan = await _translator.translate(
      assets: resolved.assets,
      scope: scope,
      selected: selected,
      plugins: resolved.directories,
    );

    final reconciliation = _reconciler.apply(
      plan.changes,
      manifest: manifest,
      force: force,
      dryRun: dryRun,
    );
    final applied = reconciliation.changes;
    final pruned = _prune(
      reconciliation.manifest,
      scope: scope,
      planned: plan.changes,
      covered: _covers(manifest, selected, plugins),
      force: force,
      dryRun: dryRun,
    );

    _report(plan, applied, pruned.entries, dryRun: dryRun);
    final retirement = _retire(
      _supersededAndReplaced(plan, applied),
      pruned.manifest,
      scope.root,
      force: force,
      dryRun: dryRun,
    );
    final recorded =
        dryRun ||
        store.save(
          from: manifest,
          to: retirement.manifest.withPlugins(
            _pluginVersions(manifest, resolved.assets.plugins, selected),
          ),
        );
    final anyFailed =
        applied.any((change) => change.outcome == ChangeOutcome.failed) ||
        [
          ...pruned.entries,
          ...retirement.entries,
        ].any((entry) => entry.outcome == ReverseOutcome.failed);
    return !recorded || anyFailed
        ? ExitCode.ioError.code
        : ExitCode.success.code;
  }

  /// Whether [selected] and [plugins] include every harness and plugin
  /// [manifest] records, so what this run does not write is no longer
  /// VGV's rather than left to a harness or plugin it skipped.
  static bool _covers(
    InstallManifest manifest,
    Set<Harness> selected,
    Set<String> plugins,
  ) =>
      manifest.entries.every(
        (entry) => entry.owner == null || selected.contains(entry.owner),
      ) &&
      manifest.plugins.entries.every(
        (recorded) =>
            selected.contains(recorded.key) &&
            plugins.containsAll(recorded.value.keys),
      );

  /// Takes back what [manifest] records in a project that [planned] no
  /// longer writes, when this run [covered] everything it records, and
  /// returns what each entry did and [manifest] without them.
  ///
  /// A file the user changed is kept, unless [force], and is theirs from
  /// now on, so it leaves the manifest either way. The user's home is
  /// never pruned: an install there is shared by every project, and
  /// `uninstall` takes it back.
  Reversal _prune(
    InstallManifest manifest, {
    required Scope scope,
    required List<PlannedChange> planned,
    required bool covered,
    required bool force,
    required bool dryRun,
  }) {
    if (scope is! ProjectScope || !covered) {
      return Reversal(entries: const [], manifest: manifest);
    }

    final writes = {for (final change in planned) change.file.path};
    final stale = [
      for (final entry in manifest.entries)
        if (!writes.contains(entry.path)) entry,
    ];
    final reversal = _auditor.reverse(
      InstallManifest(stale),
      scope.root.fileSystem,
      force: force,
      dryRun: dryRun,
    );
    if (!dryRun) _deleteEmptyDirectories(reversal.entries, scope.root);
    return Reversal(
      entries: reversal.entries,
      manifest: manifest.without([for (final entry in stale) entry.path]),
    );
  }

  /// Deletes the directories each removed entry of [entries] left empty, up
  /// to [root], warning about one that cannot be.
  void _deleteEmptyDirectories(List<ReversedEntry> entries, Directory root) {
    for (final ReversedEntry(:entry, :outcome) in entries) {
      if (outcome != ReverseOutcome.removed) continue;
      try {
        root.fileSystem.file(entry.path).parent.deleteEmptyUpTo(root);
      } on FileSystemException catch (error) {
        _logger.warn(
          'Could not delete the empty directories above ${entry.path}: '
          '${error.description}',
        );
      }
    }
  }

  /// Why there is nothing to install when no harness is selected.
  static final String _noHarnessSelected =
      'No harness selected. Install one of '
      '${Harness.values.map((harness) => harness.displayName).join(', ')}, '
      'or pass --only to name one explicitly.';

  /// Why `--refresh` installs nothing when the manifest records no plugins.
  static const String _nothingToRefresh =
      'Nothing to refresh: no previous install recorded its plugins. Run '
      'install to choose them.';

  /// Throws a [UsageException] when `--refresh` is combined with an option
  /// that picks harnesses, plugins or the project, since it takes them from
  /// the user's manifest.
  void _rejectSelectionWithRefresh() {
    final picked = [
      'only',
      'plugin',
      projectFlag,
      ...Harness.values.map((harness) => harness.name),
    ].where(argResults!.wasParsed);
    if (picked.isNotEmpty) {
      usageException(
        '--$refreshFlag cannot be combined with '
        '${picked.map((option) => '--$option').join(', ')}.',
      );
    }
  }

  /// The plugins [manifest] records for [selected] that this version still
  /// pins, warning about the ones it no longer does.
  Set<String> _recordedPlugins(
    InstallManifest manifest,
    Set<Harness> selected,
  ) {
    final recorded = {
      for (final harness in selected) ...?manifest.plugins[harness]?.keys,
    };
    final pinned = {for (final plugin in vgvPlugins) plugin.name};
    final dropped = recorded.difference(pinned);
    if (dropped.isNotEmpty) {
      _logger.warn(
        'Skipping ${dropped.join(', ')}, which this version no longer '
        'installs.',
      );
    }
    return recorded.intersection(pinned);
  }

  /// Where this run installs: the project `--project` names, resolved
  /// against the working directory, or the user's [home].
  ///
  /// Throws a [UsageException] for a directory without `--project`, more
  /// than one directory, one that does not exist, or [home] itself.
  Scope _scope(Directory home) {
    final rest = argResults!.rest;
    if (argResults![projectFlag] != true) {
      if (rest.isNotEmpty) {
        usageException(
          'Unexpected argument "${rest.first}". Pass --$projectFlag to '
          'install into a directory.',
        );
      }
      return UserScope(home);
    }

    if (rest.length > 1) {
      usageException('--$projectFlag takes one directory, not ${rest.length}.');
    }
    final path = _workingDirectory.fileSystem.path;
    final project = _workingDirectory.fileSystem.directory(
      path.normalize(path.join(_workingDirectory.path, rest.firstOrNull ?? '')),
    );
    if (!project.existsSync()) {
      usageException('${project.path} is not a directory.');
    }
    // A project rooted at home would share the user install's manifest and
    // skills, and a rerun would then prune the user install.
    if (home.existsSync() &&
        path.equals(
          project.resolveSymbolicLinksSync(),
          home.resolveSymbolicLinksSync(),
        )) {
      usageException(
        '${project.path} is your home directory. Pass --$projectFlag a '
        'repository instead.',
      );
    }
    return ProjectScope(project);
  }

  /// Resolves which harnesses to configure in [scope].
  ///
  /// `--only` wins outright and bypasses detection. A project is configured
  /// for every enabled harness, since whoever clones it may use any of them.
  /// Otherwise every harness that is both enabled and actually installed is
  /// configured, since writing config for a harness the user does not have is
  /// noise. Only enabled harnesses are probed, since each probe may wait out
  /// a timeout. A harness older than it supports is warned about, and still
  /// configured.
  Future<Set<Harness>> _select(Scope scope) async {
    final only = onlyHarnesses;
    if (only != null) return only;
    if (scope is ProjectScope) return Harness.values.where(isEnabled).toSet();

    final enabled = <Harness>[];
    for (final harness in Harness.values) {
      if (isEnabled(harness)) {
        enabled.add(harness);
      } else {
        _logger.detail('Skipping ${harness.displayName}: opted out');
      }
    }

    final detections = Map.fromIterables(
      enabled,
      await Future.wait(enabled.map(_detector.detect)),
    );
    final selected = <Harness>{};

    for (final MapEntry(key: harness, value: detection) in detections.entries) {
      if (detection.installed) {
        selected.add(harness);
        _reportVersion(harness, detection);
      } else {
        _logger.info(
          '${lightYellow.wrap('skipped')} ${harness.displayName} '
          '(not installed)',
        );
      }
    }

    return selected;
  }

  /// Warns when [detection] found [harness] older than it supports, and
  /// notes when its version could not be read. Either way it is still
  /// configured, since most of what install writes works on any version.
  void _reportVersion(Harness harness, HarnessDetection detection) {
    final name = harness.displayName;
    final minimum = harness.minimumVersion;
    switch (detection.status) {
      case HarnessStatus.outdated:
        _logger.warn(
          '$name ${detection.version} is older than $minimum, the oldest '
          'version vgv_ai supports, so it may ignore some of what install '
          'writes. Update $name to $minimum or later.',
        );
      case HarnessStatus.unversioned:
        _logger.info(
          'Could not read the version of $name, so cannot tell whether it '
          'is at least $minimum.',
        );
      case HarnessStatus.supported || HarnessStatus.missing:
        break;
    }
  }

  /// The plugins to install for [selected]: the ones `--plugin` names, or
  /// when it names none, the ones the user picks in a terminal, or every
  /// pinned plugin outside one.
  ///
  /// The picker starts from the pinned plugins [manifest] records for
  /// [selected], so a rerun keeps what the user chose before, and from every
  /// pinned plugin when it records none of them. A recorded plugin the user
  /// leaves out stays installed, which the user is told, since a picker
  /// suggests otherwise.
  Set<String> _selectPlugins(InstallManifest manifest, Set<Harness> selected) {
    final names = argResults!['plugin'] as List<String>;
    if (names.isNotEmpty) return names.toSet();
    if (!_hasTerminal) {
      return {for (final plugin in vgvPlugins) plugin.name};
    }

    final recorded = {
      for (final harness in selected) ...?manifest.plugins[harness]?.keys,
    };
    final installed = [
      for (final plugin in vgvPlugins)
        if (recorded.contains(plugin.name)) plugin,
    ];
    final chosen = _logger.chooseAny(
      'Which VGV plugins should be installed?',
      choices: vgvPlugins,
      defaultValues: installed.isEmpty ? vgvPlugins : installed,
      display: (plugin) => plugin.name,
    );
    final picked = {for (final plugin in chosen) plugin.name};

    final kept = recorded.difference(picked);
    if (picked.isNotEmpty && kept.isNotEmpty) {
      _logger.info(
        'Keeping ${kept.join(', ')}, which a previous install wrote. Run '
        "${lightCyan.wrap('uninstall')} to remove VGV's plugins.",
      );
    }
    return picked;
  }

  /// The versions to record for each harness of [selected]: [installed] for
  /// the plugins this run wrote, and what [manifest] already records for the
  /// ones it skipped, whose files are still installed. Every other harness
  /// keeps what it had.
  Map<Harness, Map<String, String>> _pluginVersions(
    InstallManifest manifest,
    List<PluginRef> installed,
    Set<Harness> selected,
  ) {
    final written = {
      for (final plugin in installed) plugin.name: plugin.version,
    };
    return {
      ...manifest.plugins,
      for (final harness in selected)
        harness: {
          for (final plugin in vgvPlugins)
            plugin.name:
                ?(written[plugin.name] ??
                manifest.plugins[harness]?[plugin.name]),
        },
    };
  }

  /// Resolves and parses the [plugins] into one asset bundle, with every
  /// body naming the plugin's files where [scope] keeps them.
  ///
  /// Returns `null`, having said why, when any plugin cannot be resolved or
  /// parsed.
  Future<ResolvedAssets?> _resolveAssets(
    Directory home,
    Set<String> plugins, {
    required Scope scope,
  }) async {
    final progress = _logger.progress('Resolving plugins');

    final resolution = await _resolver.resolve(
      home,
      only: plugins,
      log: _logger.detail,
      pluginRoot: scope.pluginRoot,
    );
    switch (resolution) {
      case final ResolvedAssets resolved:
        progress.complete(
          'Resolved ${resolved.assets.skills.length} skills and '
          '${resolved.assets.agents.length} agents',
        );
        return resolved;
      case UnavailableAssets(:final plugin, :final reasons):
        progress.fail('Could not resolve $plugin');
        for (final reason in reasons) {
          _logger.err('  - $reason');
        }
        return null;
      case UnparseableAssets(:final plugin, :final error):
        progress.fail('Could not parse $plugin');
        _logger.err('  - $error');
        return null;
    }
  }

  /// The files [plan] supersedes whose replacement [applied] left holding
  /// VGV's contributions, so a failed write never costs the user both
  /// copies.
  Set<String> _supersededAndReplaced(
    TranslationPlan plan,
    List<AppliedChange> applied,
  ) {
    final replaced = {
      for (final AppliedChange(:change, :outcome) in applied)
        if (_replaced.contains(outcome)) change.file.path,
    };
    return {
      for (final MapEntry(key: old, value: current) in plan.superseded.entries)
        if (replaced.contains(current)) old,
    };
  }

  /// Takes back the [superseded] files [manifest] records, deletes the
  /// folders that leaves empty, and reports each.
  ///
  /// A file the user changed since is kept unless [force] is set, and
  /// warned about either way.
  Reversal _retire(
    Set<String> superseded,
    InstallManifest manifest,
    Directory home, {
    required bool force,
    required bool dryRun,
  }) {
    final fileSystem = home.fileSystem;
    // Without force a changed file is skipped, which already says so.
    final edited = {
      if (force)
        for (final path in superseded)
          if (manifest[path] case final entry?)
            if (_auditor.verify(entry, fileSystem).status ==
                EntryStatus.drifted)
              path,
    };
    final reversal = _auditor.reverse(
      manifest,
      fileSystem,
      paths: superseded,
      force: force,
      dryRun: dryRun,
    );
    for (final ReversedEntry(:entry, :outcome, :error) in reversal.entries) {
      _reportRetired(
        entry.path,
        outcome,
        error: error,
        edited: edited.contains(entry.path),
        dryRun: dryRun,
      );
    }
    if (!dryRun) deleteEmptyDirectories(reversal.entries, home, _logger);
    return reversal;
  }

  /// Reports what taking back the superseded file at [path] did.
  void _reportRetired(
    String path,
    ReverseOutcome outcome, {
    required String? error,
    required bool edited,
    required bool dryRun,
  }) {
    switch (outcome) {
      case ReverseOutcome.failed:
        _logger.err('Could not remove $path: $error');
      case ReverseOutcome.skipped || ReverseOutcome.unparseable:
        _logger.warn(
          'Kept $path, which an earlier version wrote and you have changed '
          "since. Pass ${lightCyan.wrap('--force')} to remove it.",
        );
      case ReverseOutcome.removed || ReverseOutcome.partial when edited:
        _logger.warn(
          '${dryRun ? 'Would remove' : 'Removed'} $path, which an earlier '
          'version wrote and you have changed since.',
        );
      case ReverseOutcome.removed || ReverseOutcome.partial when dryRun:
        _logger.info('Would remove $path');
      case ReverseOutcome.removed || ReverseOutcome.partial:
        _logger.detail('Removed $path, which an earlier version wrote');
      case ReverseOutcome.missing:
    }
  }

  /// Prints what could not be translated, the files that could not be
  /// written or kept the user's values, what was taken back as [pruned],
  /// and then what was written per owner.
  void _report(
    TranslationPlan plan,
    List<AppliedChange> applied,
    List<ReversedEntry> pruned, {
    required bool dryRun,
  }) {
    _reportNotes(plan);
    _reportOutcomes(applied, dryRun: dryRun);
    _reportKept(applied);
    _reportPruned(pruned, dryRun: dryRun);
    _reportWritten(applied, pruned, dryRun: dryRun);
  }

  /// Reports each file VGV no longer writes: removed, kept because the user
  /// changed it, or failed.
  void _reportPruned(List<ReversedEntry> pruned, {required bool dryRun}) {
    for (final ReversedEntry(:entry, :outcome, :error) in pruned) {
      final path = entry.path;
      switch (outcome) {
        case ReverseOutcome.removed when dryRun:
          _logger.info('Would remove $path');
        case ReverseOutcome.removed:
          _logger.detail('Removed $path');
        case ReverseOutcome.failed:
          _logger.err('Could not remove $path: $error');
        // The user already deleted it, which is what pruning would do.
        case ReverseOutcome.missing:
          break;
        // Skipped, partly reversed or unparseable: the user changed it.
        case _:
          _logger.warn(
            'Kept $path, which VGV no longer writes but you have changed. '
            'It is yours now.',
          );
      }
    }
  }

  /// Warns about everything that could not be translated, per owner.
  void _reportNotes(TranslationPlan plan) {
    for (final note in plan.shared?.notes ?? const <TranslationNote>[]) {
      _logger.warn('${_ownerName(null)}: $note');
    }
    for (final MapEntry(key: harness, value: result)
        in plan.harnesses.entries) {
      for (final note in result.notes) {
        _logger.warn('${_ownerName(harness)}: $note');
      }
    }
  }

  /// Reports each file that failed, could not be parsed, or was written.
  void _reportOutcomes(List<AppliedChange> applied, {required bool dryRun}) {
    for (final AppliedChange(:change, :outcome, :error) in applied) {
      final path = change.file.path;
      switch (outcome) {
        case ChangeOutcome.failed:
          _logger.err('Could not update $path: $error');
        case ChangeOutcome.unparseable:
          _logger.warn(
            'Left $path alone because it could not be parsed. If it has '
            "comments, add VGV's settings to it by hand.",
          );
        // A dry run exists to show what would change, so its paths are
        // always printed.
        case _ when _wrote.contains(outcome) && dryRun:
          _logger.info('Would write $path');
        case _ when _wrote.contains(outcome):
          _logger.detail('Wrote $path');
        case _:
      }
    }
  }

  /// Warns about each file where the user's values were kept over VGV's.
  void _reportKept(List<AppliedChange> applied) {
    final kept = applied.where(
      (change) => _keptUserValues.contains(change.outcome),
    );
    for (final AppliedChange(:change) in kept) {
      _logger.warn('Kept your values in ${change.file.path}');
    }
    if (kept.isNotEmpty) {
      _logger.info("Pass ${lightCyan.wrap('--force')} to take VGV's.");
    }
  }

  /// Summarizes how many files were written per owner and how many of
  /// [pruned] were removed, or that nothing needed to be.
  void _reportWritten(
    List<AppliedChange> applied,
    List<ReversedEntry> pruned, {
    required bool dryRun,
  }) {
    final written = applied
        .where((change) => _wrote.contains(change.outcome))
        .groupListsBy((change) => change.change.harness);
    final removed = pruned.where(
      (entry) => entry.outcome == ReverseOutcome.removed,
    );

    if (written.isEmpty && removed.isEmpty) {
      final settled =
          applied.every(
            (change) => change.outcome == ChangeOutcome.unchanged,
          ) &&
          pruned.every((entry) => entry.outcome == ReverseOutcome.missing);
      if (settled) _logger.info('Everything is already up to date.');
      return;
    }

    for (final MapEntry(key: harness, value: changes) in written.entries) {
      _logger.info('  ${_ownerName(harness)}: ${changes.length} file(s)');
    }
    if (removed.isNotEmpty) {
      _logger.info('  Removed ${removed.length} file(s) VGV no longer writes');
    }

    _logger.info(
      dryRun
          ? '\n${lightYellow.wrap('--check')} so nothing was written.'
          : '\nRestart your coding agents to pick up the changes.',
    );
  }
}

/// How [harness] is named in the report, with the shared skills as `Shared`.
String _ownerName(Harness? harness) => harness?.displayName ?? 'Shared';
