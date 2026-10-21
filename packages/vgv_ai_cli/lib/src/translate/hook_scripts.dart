import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/copy_source.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template hook_scripts}
/// A harness's copy of each plugin's `hooks` folder under the hooks root
/// and the plugin's name, with the harness's [preamble] below the shebang
/// of every script a hook runs. `__ROOT__`, `__AGENT__` and `__COMPAT__`
/// in it are replaced with quoted shell words: the plugin root, the agent
/// the hook is scoped to or an empty string, and the compat script's path.
///
/// The whole folder comes, since scripts source their neighbours; the
/// plugin's `hooks.json` does not, the translator spells it.
/// {@endtemplate}
class const HookScripts({
  /// The harness the copy is for.
  required final Harness harness,

  /// What goes below the shebang of a script a hook runs.
  required final String preamble,
}) {
  /// {@macro hook_scripts}
  this;

  /// The folder a Claude Code plugin keeps its hooks in.
  static const hooksFolder = 'hooks';

  /// The handler type that runs a shell command; `mcp_tool` and `prompt`
  /// name no script.
  static const commandType = 'command';

  /// The plugin's own hook registry, relative to its root.
  static final String _registry = p.join(hooksFolder, 'hooks.json');

  /// What a plugin may be named, since its name becomes a folder under the
  /// hooks root.
  static final _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// A file under the hooks folder a command names, relative to the plugin
  /// root, quoted or not.
  static final _hooksFile = RegExp(
    '${RegExp.escape(HookCommand.rootPlaceholder)}/($hooksFolder/[^\\s"\']+)',
  );

  /// A command that runs its script through bash, whatever the shebang says.
  static final _bashCommand = RegExp(r'^\s*bash\s');

  /// A shebang that names bash.
  static final _bashShebang = RegExp(r'^#!.*\bbash\b');

  /// Whether [hook]'s plugin name is safe as a folder name.
  static bool safelyNamed(HookAsset hook) => _namePattern.hasMatch(hook.plugin);

  /// Whether [hook] runs a shell command, which is what needs the preamble.
  static bool runsCommand(HookAsset hook) =>
      hook.commands.any((command) => command.type == commandType);

  /// One note per handler type in [hooks] that runs no shell command, which
  /// [harness] leaves out.
  List<TranslationNote> handlerNotes(List<HookAsset> hooks) {
    final counts = hooks
        .expand((hook) => hook.commands)
        .map((command) => command.type)
        .where((type) => type != commandType)
        .groupFoldBy<String, int>(
          (type) => type,
          (count, _) => (count ?? 0) + 1,
        );
    return [
      for (final MapEntry(key: type, value: count) in counts.entries)
        TranslationNote(
          subject: '$count $type handler(s)',
          reason:
              '${harness.displayName} runs a shell command only, so they are '
              'left out',
        ),
    ];
  }

  /// Where the copy of [hook]'s plugin goes under [hooksRoot].
  static Directory copyRoot(HookAsset hook, Directory hooksRoot) =>
      hooksRoot.childDirectory(hook.plugin);

  /// [command] with the hooks folder pointing at the copy and the rest of
  /// the plugin at itself, both quoted.
  static String command(
    HookCommand command,
    HookAsset hook, {
    required Directory hooksRoot,
  }) => command.command
      .replaceAll(
        '${HookCommand.rootPlaceholder}/$hooksFolder/',
        '${quoted(copyRoot(hook, hooksRoot).path)}/$hooksFolder/',
      )
      .replaceAll(HookCommand.rootPlaceholder, quoted(hook.pluginRoot.path));

  /// [value] as one double-quoted shell word.
  static String quoted(String value) =>
      '"${value.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m[0]}')}"';

  /// The copy of every plugin [hooks] belong to, [compat] being the script
  /// the preamble sources, and a note for each file that could not be
  /// copied as intended.
  HookCopy copy(
    List<HookAsset> hooks, {
    required Directory hooksRoot,
    required File compat,
  }) {
    final files = <_HookFile>[];
    final notes = <TranslationNote>[];
    for (final plugin in hooks.groupListsBy((h) => h.plugin).values) {
      _scanPlugin(plugin, files: files, notes: notes);
    }
    return HookCopy(
      files: [
        for (final file in files)
          PlannedChange(
            file: hooksRoot.fileSystem.file(
              p.join(copyRoot(file.hook, hooksRoot).path, file.relative),
            ),
            bytes: file.bytes(compat),
            harness: harness,
            source: file.source,
          ),
      ],
      notes: notes,
    );
  }

  /// How [hooks] use each script under the hooks folder, by relative path.
  static Map<String, _ScriptUse> _scriptUses(List<HookAsset> hooks) {
    final uses = <String, _ScriptUse>{};
    for (final hook in hooks) {
      for (final command in hook.commands) {
        if (command.type == commandType) _noteUses(uses, hook, command);
      }
    }
    return uses;
  }

  /// Records each script [command] names in [uses].
  static void _noteUses(
    Map<String, _ScriptUse> uses,
    HookAsset hook,
    HookCommand command,
  ) {
    for (final match in _hooksFile.allMatches(command.command)) {
      uses.putIfAbsent(match[1]!, _ScriptUse.new)
        ..agents.add(hook.agent)
        ..bashCommand |= _bashCommand.hasMatch(command.command);
    }
  }

  /// Adds one plugin's hooks folder to [files], [hooks] being all of its.
  void _scanPlugin(
    List<HookAsset> hooks, {
    required List<_HookFile> files,
    required List<TranslationNote> notes,
  }) {
    final hook = hooks.first;
    if (!safelyNamed(hook)) {
      notes.add(
        TranslationNote(
          subject: hook.plugin,
          reason:
              'its name is not safe as a folder name, so its hooks were not '
              'installed',
        ),
      );
      return;
    }

    final folder = hook.pluginRoot.childDirectory(hooksFolder);
    // The cache was cleared since resolution; say so rather than throw.
    if (!folder.existsSync()) {
      notes.add(
        TranslationNote(
          subject: hook.plugin,
          reason:
              'its hooks folder ${folder.path} has gone away, so its hooks '
              'were registered but their scripts were not written',
        ),
      );
      return;
    }

    final scripts = _scriptUses(hooks);
    // followLinks off: a symlink cycle would otherwise hang the walk.
    final entities = folder.listSync(recursive: true, followLinks: false);
    for (final entity in entities.where((e) => e is! Directory)) {
      final relative = p.relative(entity.path, from: hook.pluginRoot.path);
      if (relative == _registry) continue;

      final copy = _copyOf(
        entity,
        hook,
        relative: relative,
        use: scripts[relative],
        notes: notes,
      );
      if (copy != null) files.add(copy);
    }
  }

  /// [entity] as the copy holds it, or null when it cannot be copied.
  _HookFile? _copyOf(
    FileSystemEntity entity,
    HookAsset hook, {
    required String relative,
    required _ScriptUse? use,
    required List<TranslationNote> notes,
  }) {
    final subject = '${hook.plugin}/$relative';
    final source = entity.copySource(subject, notes);
    if (source == null) return null;

    final file = _HookFile(
      hook: hook,
      source: source,
      relative: relative,
      preamble: preamble,
    );
    return use == null
        ? file
        : _withPreamble(file, subject: subject, use: use, notes: notes);
  }

  /// [file] with the [preamble] below its shebang. A script bash does not
  /// run, or that is not UTF-8, is copied as it is and reported in [notes].
  _HookFile _withPreamble(
    _HookFile file, {
    required String subject,
    required _ScriptUse use,
    required List<TranslationNote> notes,
  }) {
    final String script;
    try {
      script = utf8.decode(file.source.readAsBytesSync());
    } on FormatException {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'it is not UTF-8 text, so it was copied as it is and '
              '${harness.displayName} hands it its own payload',
        ),
      );
      return file;
    }

    if (!use.bashCommand && !_bashShebang.hasMatch(script)) {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'it is not a bash script, so it was copied as it is and '
              '${harness.displayName} hands it its own payload',
        ),
      );
      return file;
    }

    final String? agent;
    if (use.agents.length == 1) {
      agent = use.agents.single;
    } else {
      agent = null;
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'hooks of more than one agent scope run it, so it runs for '
              'every agent',
        ),
      );
    }

    // A shebang-only script has no newline to split at.
    final newline = script.indexOf('\n');
    final shebang = !script.startsWith('#!')
        ? 0
        : newline < 0
        ? script.length
        : newline + 1;
    final head = script.substring(0, shebang);
    return _HookFile(
      hook: file.hook,
      source: file.source,
      relative: file.relative,
      preamble: preamble,
      splice: _Splice(
        head: head.isNotEmpty && !head.endsWith('\n') ? '$head\n' : head,
        tail: script.substring(shebang),
        agent: agent,
      ),
    );
  }
}

/// {@template hook_copy}
/// What [HookScripts.copy] produced: the files of the copy and a note for
/// each that could not be copied as intended.
/// {@endtemplate}
class const HookCopy({
  required final List<PlannedChange> files,
  required final List<TranslationNote> notes,
}) {
  /// {@macro hook_copy}
  this;
}

/// One file of a plugin's hooks folder as the copy holds it; [hook] is any
/// hook of the plugin, [relative] its path from the plugin root, and
/// [splice] where [preamble] goes when a hook runs it.
class const _HookFile({
  required final HookAsset hook,
  required final File source,
  required final String relative,
  required final String preamble,
  final _Splice? splice,
}) {
  /// The copy's bytes, [compat] being the script the preamble sources.
  List<int> bytes(File compat) => switch (splice) {
    final splice? => utf8.encode(splice.render(preamble, hook, compat)),
    _ => source.readAsBytesSync(),
  };
}

/// Where a preamble goes in a script: between [head], the shebang or
/// nothing, and [tail], the rest, scoped to [agent] when one is set.
class const _Splice({
  required final String head,
  required final String tail,
  required final String? agent,
}) {
  String render(String preamble, HookAsset hook, File compat) {
    final body = preamble
        .replaceAll('__ROOT__', HookScripts.quoted(hook.pluginRoot.path))
        .replaceAll('__AGENT__', HookScripts.quoted(agent ?? ''))
        .replaceAll('__COMPAT__', HookScripts.quoted(compat.path));
    return '$head$body$tail';
  }
}

/// How the hooks use one script: run through bash by a command, and the
/// agent scopes of the hooks naming it, null being the plugin's own.
class _ScriptUse {
  bool bashCommand = false;
  final Set<String?> agents = {};
}
