import 'dart:convert';

import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:toml/toml.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/harness_translator.dart';
import 'package:vgv_ai_cli/src/translate/hook_scripts.dart';
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
  String settings(PluginAssets assets, {required Directory home}) =>
      TomlDocument.fromMap({
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
              'command': HookScripts.command(
                command,
                hook,
                hooksRoot: hooksRoot,
              ),
              'timeout': ?command.timeout,
            },
        ],
      });
    }
    return events.isEmpty ? null : jsonEncode({'hooks': events});
  }

  /// Codex's own copy of each plugin's `hooks` folder, with [preamble] at
  /// the top of every script a hook runs.
  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => _scripts.files(assets.hooks, hooksRoot: hooksRoot);

  /// What [hookFiles] could not copy as intended, and the trust step that
  /// starts the hooks.
  @override
  List<TranslationNote> notes(PluginAssets assets) => [
    ...super.notes(assets),
    ..._scripts.notes(assets.hooks),
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

  static const _scripts = HookScripts(
    harness: Harness.codex,
    preamble: preamble,
  );

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
