import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template hook_scripts}
/// A harness's copy of each plugin's `hooks` folder, with the harness's own
/// [preamble] at the top of every script a hook runs. `__ROOT__` in it is
/// replaced with the plugin root and `__AGENT__` with the agent the hook is
/// scoped to, or nothing, each as one shell word.
///
/// The whole folder comes along, because a script sources its neighbours.
/// The plugin's `hooks.json` is left out, since the translator spells it.
/// {@endtemplate}
class const HookScripts({
  /// The harness the copy is for.
  required final Harness harness,

  /// What goes at the top of a copied script, below its shebang.
  required final String preamble,
}) {
  /// The folder a Claude Code plugin keeps its hooks in.
  static const hooksFolder = 'hooks';

  /// The plugin's own hook registry, relative to its root.
  static final String _registry = p.join(hooksFolder, 'hooks.json');

  /// The handler type whose `command` is a shell command.
  ///
  /// Codex also takes an `mcp_tool` handler, and Claude a `prompt` one.
  /// Neither runs a script, so neither names one to copy.
  static const commandType = 'command';

  /// A file under the plugin's hooks folder that a command names, relative
  /// to the plugin root. Stops at a quote, so a quoted path is still found.
  static final _hooksFile = RegExp(
    '${RegExp.escape(HookCommand.rootPlaceholder)}/($hooksFolder/[^\\s"\']+)',
  );

  /// A command that runs its script through bash, whatever the shebang says.
  static final _bashCommand = RegExp(r'^\s*bash\s');

  /// A shebang that names bash.
  static final _bashShebang = RegExp(r'^#!.*\bbash\b');

  /// Where the copy of [hook]'s plugin goes under [hooksRoot].
  static Directory copyRoot(HookAsset hook, Directory hooksRoot) =>
      hooksRoot.childDirectory(hook.plugin);

  /// What [command] runs as, once its paths are real.
  ///
  /// A file under the plugin's hooks folder is read from the copy under
  /// [hooksRoot], which is where the preamble is. Anything else the plugin
  /// ships stays where it is, so the rest of the placeholder becomes the
  /// plugin's own root. Both are quoted, because a plugin under the user's
  /// home sits at a path that may hold a space.
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

  /// [value] as one double-quoted shell word, which concatenates cleanly
  /// with the rest of a path whether or not the command quoted it.
  static String quoted(String value) =>
      '"${value.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m[0]}')}"';

  /// The copy of every plugin [hooks] belong to, under [hooksRoot] and the
  /// plugin's name.
  ///
  /// What could not be copied as intended is reported by [notes].
  List<PlannedChange> files(
    List<HookAsset> hooks, {
    required Directory hooksRoot,
  }) => [
    for (final file in _scan(hooks).files)
      PlannedChange(
        file: hooksRoot.fileSystem.file(
          p.join(copyRoot(file.hook, hooksRoot).path, file.relative),
        ),
        bytes: file.bytes,
        harness: harness,
        source: file.source,
      ),
  ];

  /// What [files] could not copy as intended.
  List<TranslationNote> notes(List<HookAsset> hooks) => _scan(hooks).notes;

  /// How the scripts under the hooks folder are used by [hooks], keyed by
  /// their path relative to the plugin root.
  static Map<String, _ScriptUse> _scriptUses(List<HookAsset> hooks) {
    final uses = <String, _ScriptUse>{};
    for (final hook in hooks) {
      for (final command in hook.commands) {
        if (command.type == commandType) _noteUses(uses, hook, command);
      }
    }
    return uses;
  }

  /// Records in [uses] each script [command] names, as [hook] uses it.
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

  /// Every file of every plugin's hooks folder, as the copy holds it, and a
  /// note for each one that could not be copied as intended.
  _HookScan _scan(List<HookAsset> hooks) {
    final files = <_HookFile>[];
    final notes = <TranslationNote>[];
    for (final plugin in hooks.groupListsBy((h) => h.plugin).values) {
      _scanPlugin(plugin, files: files, notes: notes);
    }
    return _HookScan(files: files, notes: notes);
  }

  /// Adds the files of one plugin's hooks folder to [files], [hooks] being
  /// every hook of that plugin.
  void _scanPlugin(
    List<HookAsset> hooks, {
    required List<_HookFile> files,
    required List<TranslationNote> notes,
  }) {
    final hook = hooks.first;
    final folder = hook.pluginRoot.childDirectory(hooksFolder);

    // A cache cleared between resolution and translation. The hooks are
    // still registered, so say why they will fail rather than throw.
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
    // followLinks is off so a symlinked directory is reported rather than
    // walked, which a cycle would otherwise turn into a hang.
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

  /// [entity] as the copy holds it, with the preamble when [use] says a hook
  /// runs it, or null when it cannot be copied.
  _HookFile? _copyOf(
    FileSystemEntity entity,
    HookAsset hook, {
    required String relative,
    required _ScriptUse? use,
    required List<TranslationNote> notes,
  }) {
    final subject = '${hook.plugin}/$relative';
    final source = _sourceFile(entity, subject, notes);
    if (source == null) return null;

    final bytes = source.readAsBytesSync();
    return _HookFile(
      hook: hook,
      source: source,
      relative: relative,
      bytes: use == null
          ? bytes
          : _withPreamble(
              bytes,
              hook.pluginRoot,
              subject: subject,
              use: use,
              notes: notes,
            ),
    );
  }

  /// Resolves [entity] to a readable file, or reports why it cannot be.
  static File? _sourceFile(
    FileSystemEntity entity,
    String subject,
    List<TranslationNote> notes,
  ) {
    if (entity is File) return entity;

    final String resolved;
    try {
      resolved = entity.resolveSymbolicLinksSync();
    } on FileSystemException {
      notes.add(
        TranslationNote(
          subject: subject,
          reason: 'the symlink points at something that does not exist',
        ),
      );
      return null;
    }

    final file = entity.fileSystem.file(resolved);
    if (file.existsSync()) return file;

    notes.add(
      TranslationNote(
        subject: subject,
        reason: 'the symlink points at a directory, which is not copied',
      ),
    );
    return null;
  }

  /// [bytes] with the [preamble] inserted below the shebang line, scoped to
  /// the one agent [use] says declared it, if one did.
  ///
  /// The preamble is bash, so it goes only into a script bash runs: one whose
  /// shebang names bash, or one its command runs through bash. Any other
  /// script, and one that is not UTF-8 text, is copied as it is and reported
  /// in [notes], since the harness will then hand it its own payload. A
  /// script named by hooks of more than one scope cannot be scoped to one
  /// agent, so it runs for every agent and is reported too.
  List<int> _withPreamble(
    List<int> bytes,
    Directory pluginRoot, {
    required String subject,
    required _ScriptUse use,
    required List<TranslationNote> notes,
  }) {
    final String script;
    try {
      script = utf8.decode(bytes);
    } on FormatException {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'it is not UTF-8 text, so it was copied as it is and '
              '${harness.displayName} hands it its own payload',
        ),
      );
      return bytes;
    }

    final shebang = script.startsWith('#!') ? script.indexOf('\n') + 1 : 0;
    if (!use.bashCommand && !_bashShebang.hasMatch(script)) {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'it is not a bash script, so it was copied as it is and '
              '${harness.displayName} hands it its own payload',
        ),
      );
      return bytes;
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

    final body = preamble
        .replaceAll('__ROOT__', quoted(pluginRoot.path))
        .replaceAll('__AGENT__', quoted(agent ?? ''));
    return utf8.encode(
      '${script.substring(0, shebang)}$body${script.substring(shebang)}',
    );
  }
}

/// One file of a plugin's hooks folder, as the copy will hold it.
class const _HookFile({
  /// A hook of the plugin the file belongs to, which names the copy's root.
  required final HookAsset hook,

  /// The file it is copied from, which carries the mode across.
  required final File source,

  /// Where it sits, relative to the plugin root.
  required final String relative,

  /// What the copy holds: the source, with the preamble when it is a script
  /// a hook runs.
  required final List<int> bytes,
});

/// What a pass over the plugins' hooks folders found.
class const _HookScan({
  required final List<_HookFile> files,
  required final List<TranslationNote> notes,
});

/// How the hooks use one script: whether a command runs it through bash, and
/// the agent scopes of the hooks that name it, null being the plugin's own.
class _ScriptUse {
  bool bashCommand = false;
  final Set<String?> agents = {};
}
