import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
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

  /// The plugins' hooks, as `~/.codex/hooks.json` spells them.
  ///
  /// Codex's hooks file has the same shape as Claude's, down to `timeout`
  /// being seconds. Two things are spelled differently here: the tool names
  /// the matchers name, and where the commands point, which is Codex's own
  /// copy of each plugin's `hooks` folder under [hooksRoot], the one
  /// [hookFiles] writes. The copy is where the third difference, the payload,
  /// is answered.
  ///
  /// Codex runs no hook it has not been told to trust, however, so writing
  /// this file is half of it and [notes] says the other half.
  ///
  /// See https://developers.openai.com/codex/hooks.
  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) {
    final events = <String, List<Object?>>{};
    for (final hook in assets.hooks) {
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

  /// Codex's own copy of each plugin's `hooks` folder, under [hooksRoot] and
  /// the plugin's name, with [preamble] at the top of every script a hook
  /// runs.
  ///
  /// The whole folder comes along, because a script sources its neighbours
  /// and reads files beside it by its own location. The one exception is the
  /// plugin's `hooks.json`, which is what [hooks] translated, so a copy of it
  /// would only mislead. A file is copied from its source so it keeps its
  /// mode, which matters for a hook that runs its script directly.
  ///
  /// What could not be copied as intended is reported by [notes].
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => [
    for (final file in _scan(assets).files)
      PlannedChange(
        file: hooksRoot.fileSystem.file(
          p.join(_copyRoot(file.hook, hooksRoot).path, file.relative),
        ),
        bytes: file.bytes,
        harness: harness,
        source: file.source,
      ),
  ];

  /// What [hookFiles] could not copy as intended, and the trust step that
  /// starts the hooks.
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

  /// What goes at the top of Codex's copy of a hook script, below its
  /// shebang, so a script written for Claude Code runs as written.
  ///
  /// It answers the two things Codex hands a script differently. It sets
  /// `CLAUDE_PLUGIN_ROOT`, which Codex does not and which a script may read
  /// to find the plugin's other files, to the plugin's real location. And it
  /// rewrites a file edit: Claude Code sends one `Edit` or `Write` per file,
  /// naming it in `tool_input.file_path`, where Codex sends one `apply_patch`
  /// holding the patch text and names no file. So the preamble reads the
  /// files out of the patch headers and runs the script once per file that
  /// is on disk, each time with the payload Claude Code would have sent,
  /// then exits with the first failure and prints the first answer, so the
  /// harness sees one decision. Any other payload, and every payload when jq
  /// is missing, reaches the script as it came.
  ///
  /// A hook an agent declared for itself is scoped the same way Claude Code
  /// scopes it: Codex names the agent a tool call came from in `agent_type`,
  /// so the script stands aside for any other. Without jq that cannot be
  /// read, and the script runs as it would for every agent.
  ///
  /// It is bash, as the plugins' scripts are, so it goes only into a script
  /// bash runs. `__ROOT__` is replaced with the plugin root and `__AGENT__`
  /// with the agent the hook is scoped to, or nothing, each as one shell
  /// word.
  static const preamble = r'''
# Added by vgv_ai install so this script, written for Claude Code, runs under
# Codex. Edits here are overwritten on the next run.
#
# Codex sets no CLAUDE_PLUGIN_ROOT, so it is set to the plugin's real files.
# And Codex reports a file edit as one apply_patch holding the patch text,
# where Claude Code sends an Edit or Write per file, naming it in
# tool_input.file_path. So the script below runs once per file the patch
# touches, each time with the payload Claude Code would have sent, and this
# exits with the first failure and prints the first answer. Any other payload
# reaches it as it came, and so does every payload when jq is missing.
export CLAUDE_PLUGIN_ROOT=__ROOT__
vgv_agent=__AGENT__
if [ -z "${VGV_CLAUDE_PAYLOAD:-}" ] && command -v jq > /dev/null 2>&1; then
  vgv_payload=$(cat)
  # A hook an agent declared for itself runs for that agent alone. Codex
  # names the agent a tool call came from in agent_type, and nothing at all
  # outside a subagent.
  if [ -n "$vgv_agent" ]; then
    vgv_caller=$(printf '%s' "$vgv_payload" | jq -r '.agent_type // ""')
    [ "$vgv_caller" = "$vgv_agent" ] || exit 0
  fi
  # One line per file of an apply_patch: the tool Claude Code would have
  # named, a tab, and the path resolved against the payload's own cwd, since
  # a patch header names a file relative to the session root when the model
  # wrote it that way. Any other tool's payload yields no lines, however much
  # its text may look like a patch.
  vgv_edits=$(printf '%s' "$vgv_payload" | jq -r '
    select(.tool_name == "apply_patch")
    | ((.cwd // ".") | rtrimstr("/")) as $cwd
    | .tool_input.command // ""
    | scan("(?m)^\\*\\*\\* (Add File|Update File|Move to): (.+)$")
    | (if .[0] == "Add File" then "Write" else "Edit" end)
      + "\t" + (.[1] | if startswith("/") then . else $cwd + "/" + . end)
  ' 2> /dev/null)
  vgv_status=0
  vgv_answer=""
  vgv_ran=0
  while IFS=$'\t' read -r vgv_tool vgv_file; do
    # A file not on disk is skipped: one the patch deleted, the old name of a
    # renamed one, or one it is about to add when this runs before the tool.
    [ -n "$vgv_file" ] && [ -f "$vgv_file" ] || continue
    vgv_ran=1
    vgv_output=$(printf '%s' "$vgv_payload" \
      | jq --arg tool "$vgv_tool" --arg file "$vgv_file" \
        '.tool_name = $tool | .tool_input.file_path = $file' \
      | VGV_CLAUDE_PAYLOAD=1 bash "$0")
    vgv_exit=$?
    [ "$vgv_status" -ne 0 ] || vgv_status=$vgv_exit
    [ -n "$vgv_answer" ] || vgv_answer=$vgv_output
  done <<< "$vgv_edits"
  if [ "$vgv_ran" -eq 0 ]; then
    printf '%s' "$vgv_payload" | VGV_CLAUDE_PAYLOAD=1 bash "$0"
    exit $?
  fi
  [ -z "$vgv_answer" ] || printf '%s\n' "$vgv_answer"
  exit "$vgv_status"
fi
''';

  /// The folder a Claude Code plugin keeps its hooks in.
  static const _hooksFolder = 'hooks';

  /// The plugin's own hook registry, relative to its root.
  static final String _registry = p.join(_hooksFolder, 'hooks.json');

  /// The handler type whose `command` is a shell command.
  ///
  /// Codex also takes an `mcp_tool` handler, and Claude a `prompt` one.
  /// Neither runs a script, so neither names one to copy.
  static const _commandType = 'command';

  /// A file under the plugin's hooks folder that a command names, relative
  /// to the plugin root. Stops at a quote, so a quoted path is still found.
  static final _hooksFile = RegExp(
    '${RegExp.escape(HookCommand.rootPlaceholder)}/($_hooksFolder/[^\\s"\']+)',
  );

  /// A command that runs its script through bash, whatever the shebang says.
  static final _bashCommand = RegExp(r'^\s*bash\s');

  /// A shebang that names bash.
  static final _bashShebang = RegExp(r'^#!.*\bbash\b');

  /// Where Codex's copy of [hook]'s plugin goes under [hooksRoot].
  static Directory _copyRoot(HookAsset hook, Directory hooksRoot) =>
      hooksRoot.childDirectory(hook.plugin);

  /// What [command] runs as, once its paths are real.
  ///
  /// A file under the plugin's hooks folder is read from Codex's copy, which
  /// is where the preamble is. Anything else the plugin ships stays where it
  /// is, so the rest of the placeholder becomes the plugin's own root. Both
  /// are quoted, because a plugin under the user's home sits at a path that
  /// may hold a space.
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

  /// [value] as one double-quoted shell word, which concatenates cleanly
  /// with the rest of a path whether or not the command quoted it.
  static String _quoted(String value) =>
      '"${value.replaceAllMapped(RegExp(r'[\\"$`]'), (m) => '\\${m[0]}')}"';

  /// How the scripts under the hooks folder are used by [hooks], keyed by
  /// their path relative to the plugin root.
  static Map<String, _ScriptUse> _scriptUses(List<HookAsset> hooks) {
    final uses = <String, _ScriptUse>{};
    for (final hook in hooks) {
      for (final command in hook.commands) {
        if (command.type == _commandType) _noteUses(uses, hook, command);
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
  static _HookScan _scan(PluginAssets assets) {
    final files = <_HookFile>[];
    final notes = <TranslationNote>[];
    for (final hooks in assets.hooks.groupListsBy((h) => h.plugin).values) {
      _scanPlugin(hooks, files: files, notes: notes);
    }
    return _HookScan(files: files, notes: notes);
  }

  /// Adds the files of one plugin's hooks folder to [files], [hooks] being
  /// every hook of that plugin.
  static void _scanPlugin(
    List<HookAsset> hooks, {
    required List<_HookFile> files,
    required List<TranslationNote> notes,
  }) {
    final hook = hooks.first;
    final folder = hook.pluginRoot.childDirectory(_hooksFolder);

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
  /// in [notes], since Codex will then hand it its own payload. A script
  /// named by hooks of more than one scope cannot be scoped to one agent, so
  /// it runs for every agent and is reported too.
  static List<int> _withPreamble(
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
              'it is not UTF-8 text, so it was copied as it is and Codex '
              'hands it its own payload',
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
              'it is not a bash script, so it was copied as it is and Codex '
              'hands it its own payload',
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
        .replaceAll('__ROOT__', _quoted(pluginRoot.path))
        .replaceAll('__AGENT__', _quoted(agent ?? ''));
    return utf8.encode(
      '${script.substring(0, shebang)}$body${script.substring(shebang)}',
    );
  }

  /// [hook]'s matcher as Codex spells it, and null when it declares none,
  /// which is how both harnesses spell a hook that fires for every tool.
  static String? _matcher(HookAsset hook) => switch (hook.matcher) {
    final declared? => _codexTools(declared).join('|'),
    _ => null,
  };

  /// The tools [matcher] fires for, as Codex names them.
  ///
  /// A matcher is an alternation of tool names, so each alternative goes
  /// through [CodexTool] on its own, and a name two alternatives share is
  /// written once.
  static List<String> _codexTools(String matcher) =>
      {for (final name in matcher.split('|')) ...CodexTool.codexNamesOf(name)}
          .toList();
}

/// One file of a plugin's hooks folder, as Codex's copy will hold it.
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
