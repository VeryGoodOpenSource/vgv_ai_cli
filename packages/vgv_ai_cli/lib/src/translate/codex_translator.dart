import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/codex_compat.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/model/model.dart';

/// {@template codex_translator}
/// Configures Codex.
///
/// Codex reads `~/.agents/skills` natively. Its agents are TOML.
/// {@endtemplate}
class const CodexTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.codex;

  @override
  bool get runsHooks => true;

  /// The keys Codex spells differently from `.mcp.json`.
  static const _renamedKeys = {'headers': 'http_headers'};

  /// Codex declares servers as `[mcp_servers.<name>]` tables, and a remote
  /// server's static headers as `http_headers`.
  @override
  String settings(PluginAssets assets) => TomlDocument.fromMap({
    'mcp_servers': {
      for (final server in assets.mcpServers)
        server.name: {
          for (final MapEntry(:key, :value) in server.toJson().entries)
            _renamedKeys[key] ?? key: value,
        },
    },
  }).toString();

  /// Codex requires `name` and `developer_instructions`, and drops with a
  /// warning any agent declaring no `description`, so all three are written.
  /// An agent body is a whole markdown document full of quotes, backticks and
  /// backslashes, which is why TOML serializes it rather than mustache.
  @override
  HarnessFields agent(AgentAsset agent, {required String instructions}) =>
      HarnessFields(
        toml: TomlDocument.fromMap({
          'name': agent.name,
          'description': agent.description,
          'developer_instructions': instructions,
        }).toString(),
      );

  /// The plugins' hooks as `~/.codex/hooks.json` spells them: Claude's shape,
  /// Codex's tool names, and commands pointing at the copy [hookFiles]
  /// writes. See https://developers.openai.com/codex/hooks.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks.where(_safelyNamed)) {
      events.putIfAbsent(hook.event, () => []).add({
        'matcher': ?_matcher(hook),
        'hooks': [
          for (final command in hook.commands)
            {
              'type': command.type,
              'command': _command(command, hook, hooksRoot: hooksRoot),
              'timeout': ?command.timeout,
            },
        ],
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// [compatScript], and Codex's copy of each plugin's `hooks` folder under
  /// `<hooksRoot>/<plugin>` with [codexPreamble] in every script a hook runs.
  /// The whole folder comes, since scripts source their neighbours; the
  /// plugin's `hooks.json` does not. What could not be copied as intended is
  /// reported by [notes].
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) {
    final compat = hooksRoot.childFile(compatScript);
    return [
      if (assets.hooks.any(_runsCommand))
        PlannedChange.text(
          file: compat,
          contents: codexCompatScript,
          harness: harness,
        ),
      for (final file in _scan(assets).files)
        PlannedChange(
          file: hooksRoot.fileSystem.file(
            p.join(_copyRoot(file.hook, hooksRoot).path, file.relative),
          ),
          bytes: file.bytes(compat),
          harness: harness,
          source: file.source,
        ),
    ];
  }

  /// What [hookFiles] could not copy as intended, and the trust step.
  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    ...super.notes(assets),
    ..._scan(assets).notes,
    if (assets.hooks.isNotEmpty)
      const TranslationNote(
        subject: 'the hooks written to ~/.codex/hooks.json',
        reason:
            'Codex runs no hook it has not been told to trust, so run /hooks '
            'in Codex and trust them',
      ),
  ];

  /// The file under the hooks root that holds [codexCompatScript].
  static const compatScript = 'vgv-claude-compat.sh';

  /// The folder a Claude Code plugin keeps its hooks in.
  static const _hooksFolder = 'hooks';

  /// The plugin's own hook registry, relative to its root.
  static final String _registry = p.join(_hooksFolder, 'hooks.json');

  /// The handler type that runs a shell command; `mcp_tool` and `prompt`
  /// name no script.
  static const _commandType = 'command';

  /// What a plugin may be named, since its name becomes a folder under the
  /// hooks root.
  static final _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  /// A file under the hooks folder a command names, relative to the plugin
  /// root, quoted or not.
  static final _hooksFile = RegExp(
    '${RegExp.escape(HookCommand.rootPlaceholder)}/($_hooksFolder/[^\\s"\']+)',
  );

  /// A command that runs its script through bash, whatever the shebang says.
  static final _bashCommand = RegExp(r'^\s*bash\s');

  /// A shebang that names bash.
  static final _bashShebang = RegExp(r'^#!.*\bbash\b');

  /// Whether [hook]'s plugin name is safe as a folder name.
  static bool _safelyNamed(HookAsset hook) =>
      _namePattern.hasMatch(hook.plugin);

  /// Whether [hook] runs a shell command, which is what needs the preamble.
  static bool _runsCommand(HookAsset hook) =>
      hook.commands.any((command) => command.type == _commandType);

  /// Where Codex's copy of [hook]'s plugin goes under [hooksRoot].
  static Directory _copyRoot(HookAsset hook, Directory hooksRoot) =>
      hooksRoot.childDirectory(hook.plugin);

  /// [command] with the hooks folder pointing at Codex's copy and the rest
  /// of the plugin at itself, both quoted.
  static String _command(
    HookCommand command,
    HookAsset hook, {
    required Directory hooksRoot,
  }) => command.command
      .replaceAll(
        '${HookCommand.rootPlaceholder}/$_hooksFolder/',
        '${_quoted(_copyRoot(hook, hooksRoot).path)}/$_hooksFolder/',
      )
      .replaceAll(HookCommand.rootPlaceholder, _quoted(hook.pluginRoot.path));

  /// [value] as one double-quoted shell word.
  static String _quoted(String value) =>
      '"${value.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m[0]}')}"';

  /// How [hooks] use each script under the hooks folder, by relative path.
  static Map<String, _ScriptUse> _scriptUses(List<HookAsset> hooks) {
    final uses = <String, _ScriptUse>{};
    for (final hook in hooks) {
      for (final command in hook.commands) {
        if (command.type == _commandType) _noteUses(uses, hook, command);
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

  /// Every file of every plugin's hooks folder as the copy holds it, and a
  /// note for each that could not be copied as intended.
  static _HookScan _scan(PluginAssets assets) {
    final files = <_HookFile>[];
    final notes = <TranslationNote>[];
    for (final hooks in assets.hooks.groupListsBy((h) => h.plugin).values) {
      _scanPlugin(hooks, files: files, notes: notes);
    }
    return _HookScan(files: files, notes: notes);
  }

  /// Adds one plugin's hooks folder to [files], [hooks] being all of its.
  static void _scanPlugin(
    List<HookAsset> hooks, {
    required List<_HookFile> files,
    required List<TranslationNote> notes,
  }) {
    final hook = hooks.first;
    if (!_safelyNamed(hook)) {
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

    final folder = hook.pluginRoot.childDirectory(_hooksFolder);
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
  static _HookFile? _copyOf(
    FileSystemEntity entity,
    HookAsset hook, {
    required String relative,
    required _ScriptUse? use,
    required List<TranslationNote> notes,
  }) {
    final subject = '${hook.plugin}/$relative';
    final source = _sourceFile(entity, subject, notes);
    if (source == null) return null;

    final file = _HookFile(hook: hook, source: source, relative: relative);
    return use == null
        ? file
        : _withPreamble(file, subject: subject, use: use, notes: notes);
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

  /// [file] with the [codexPreamble] below its shebang. A script bash does
  /// not run, or that is not UTF-8, is copied as it is and reported in
  /// [notes].
  static _HookFile _withPreamble(
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
              'it is not UTF-8 text, so it was copied as it is and Codex '
              'hands it its own payload',
        ),
      );
      return file;
    }

    if (!use.bashCommand && !_bashShebang.hasMatch(script)) {
      notes.add(
        TranslationNote(
          subject: subject,
          reason:
              'it is not a bash script, so it was copied as it is and Codex '
              'hands it its own payload',
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
      preamble: _Preamble(
        head: head.isNotEmpty && !head.endsWith('\n') ? '$head\n' : head,
        tail: script.substring(shebang),
        agent: agent,
      ),
    );
  }

  /// The tools Claude Code names in a matcher that Codex names differently:
  /// it writes every edit through `apply_patch`, keeping Claude's two names
  /// as aliases, and reads files through the shell.
  static const _codexToolNames = {
    'Edit': ['Edit', 'apply_patch'],
    'Write': ['Write', 'apply_patch'],
    'Read': ['Bash'],
    'Glob': ['Bash'],
    'Grep': ['Bash'],
  };

  /// A matcher that is a flat `A|B` list of tool names, the one shape whose
  /// names are mapped; any other regex is handed to Codex as written.
  static final _flatList = RegExp(r'^\w+(\|\w+)*$');

  /// [hook]'s matcher as Codex spells it, null when it declares none.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? when _flatList.hasMatch(declared) => {
      for (final name in declared.split('|'))
        ...(_codexToolNames[name] ?? [name]),
    }.join('|'),
    final declared => declared,
  };
}

/// One file of a plugin's hooks folder as Codex's copy holds it; [hook] is
/// any hook of the plugin, [relative] its path from the plugin root, and
/// [preamble] the one spliced in when a hook runs it.
class const _HookFile({
  required final HookAsset hook,
  required final File source,
  required final String relative,
  final _Preamble? preamble,
}) {
  /// The copy's bytes, [compat] being the script the preamble sources.
  List<int> bytes(File compat) => switch (preamble) {
    final preamble? => utf8.encode(preamble.render(hook.pluginRoot, compat)),
    _ => source.readAsBytesSync(),
  };
}

/// Where [codexPreamble] goes in a script: between [head], the shebang or
/// nothing, and [tail], the rest, scoped to [agent] when one is set.
class const _Preamble({
  required final String head,
  required final String tail,
  required final String? agent,
}) {
  String render(Directory pluginRoot, File compat) {
    final body = codexPreamble
        .replaceAll('__ROOT__', CodexTranslator._quoted(pluginRoot.path))
        .replaceAll('__AGENT__', CodexTranslator._quoted(agent ?? ''))
        .replaceAll('__COMPAT__', CodexTranslator._quoted(compat.path));
    return '$head$body$tail';
  }
}

/// What a pass over the plugins' hooks folders found.
class const _HookScan({
  required final List<_HookFile> files,
  required final List<TranslationNote> notes,
});

/// How the hooks use one script: run through bash by a command, and the
/// agent scopes of the hooks naming it, null being the plugin's own.
class _ScriptUse {
  bool bashCommand = false;
  final Set<String?> agents = {};
}
