import 'package:file/file.dart';
import 'package:plugin_source/plugin_source.dart';
import 'package:vgv_ai_cli/src/model/model.dart';
import 'package:vgv_ai_cli/src/translate/translate.dart';
import 'package:yaml/yaml.dart';

/// Builders shared by the per-harness translator tests, so each test file
/// asserts on translation rather than on fixture construction.
SkillAsset skillAsset(
  FileSystem fs,
  String name, {
  String body = '# Body\n',
  String description = 'what it does',
  bool userInvocable = true,
}) => SkillAsset(
  name: name,
  description: description,
  body: body,
  userInvocable: userInvocable,
  allowedTools: const [],
  portableFrontmatter: {'name': name, 'description': description},
  directory: fs.directory('/plugins/wingspan/skills/$name')
    ..createSync(recursive: true),
);

AgentAsset agentAsset(
  String name, {
  String body = 'You review code.\n',
  String description = 'reviews code',
  List<String> skills = const [],
}) => AgentAsset(
  name: name,
  description: description,
  body: body,
  skills: skills,
);

HookAsset hookAsset(
  FileSystem fs, {
  String event = 'PostToolUse',
  String? matcher,
  List<HookCommand> commands = const [
    HookCommand(
      type: 'command',
      command: r'bash ${PLUGIN_ROOT}/hooks/scripts/analyze.sh',
      timeout: 30,
    ),
  ],
}) {
  final root = fs.directory('/plugins/vgv-wingspan')
    ..createSync(recursive: true);
  final hooks = root.childDirectory('hooks');
  hooks.childFile('hooks.json')
    ..createSync(recursive: true)
    ..writeAsStringSync('{"hooks": {}}\n');
  hooks.childDirectory('scripts').childFile('analyze.sh')
    ..createSync(recursive: true)
    ..writeAsStringSync('#!/bin/bash\nsource common.sh\necho hi\n');
  hooks.childDirectory('scripts').childFile('common.sh')
    ..createSync(recursive: true)
    ..writeAsStringSync('hi() { echo hi; }\n');
  return HookAsset(
    event: event,
    matcher: matcher,
    commands: commands,
    plugin: 'vgv-wingspan',
    pluginRoot: root,
  );
}

PluginAssets pluginAssets({
  List<SkillAsset> skills = const [],
  List<AgentAsset> agents = const [],
  List<MCPServer> mcpServers = const [],
  List<HookAsset> hooks = const [],
}) => PluginAssets(
  skills: skills,
  agents: agents,
  mcpServers: mcpServers,
  hooks: hooks,
);

/// Parses a rendered `---` fenced frontmatter block back into its values.
Map<String, Object?> frontmatterValues(Object? rendered) {
  final lines = (rendered! as String).split('\n');
  final yaml = loadYaml(lines.sublist(1, lines.lastIndexOf('---')).join('\n'));
  return Map<String, Object?>.from(yaml as Map);
}

/// A translator that spells hooks and the files beside them, yet declares it
/// runs none, so a test can check the flag is what the callers read.
class const DeclinedHooksTranslator() extends HarnessTranslator {
  @override
  Harness get harness => Harness.pi;

  @override
  String? hooks(PluginAssets assets, {required Directory hooksRoot}) => '{}';

  @override
  List<PlannedChange> hookFiles(
    PluginAssets assets, {
    required Directory hooksRoot,
  }) => [
    PlannedChange.text(
      file: hooksRoot.childFile('declined.sh'),
      contents: '',
      harness: harness,
    ),
  ];
}
