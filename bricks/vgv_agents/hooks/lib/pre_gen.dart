import 'dart:convert';

import 'package:mason/mason.dart';

/// Harness flags the brick understands, in reporting order.
const harnesses = <String>['claude', 'gemini', 'codex', 'opencode', 'pi'];

/// Plugins enabled on the Claude Code side.
const vgvPlugins = <String>['vgv-wingspan', 'vgv-ai-flutter-plugin'];

const _json = JsonEncoder.withIndent('  ');

/// Prepares the vars the `vgv_agents` templates render against.
///
/// The settings fragments are built here rather than in mustache. A template
/// loop cannot know which iteration is last, so it cannot place separators
/// correctly, and any JSON or TOML it produced would have to be re-indented
/// anyway. The templates keep what they are good at: choosing which files
/// exist per harness, and composing the markdown block from partials.
Future<void> run(HookContext context) async {
  final vars = Map<String, dynamic>.from(context.vars);

  final selected = harnesses.where((h) => vars[h] == true).toList();
  if (selected.isEmpty) {
    context.logger.err(
      'No harness selected. Enable at least one of: ${harnesses.join(', ')}.',
    );
    throw Exception('no harness selected');
  }

  final skills = _listOfMaps(vars['skills']);
  final agents = _listOfMaps(vars['agents']);
  final mcpServers = _mapOfMaps(vars['mcp_servers']);
  final marketplace = vars['marketplace'] as String;
  final skillsRoot = vars['skills_root'] as String;

  context.vars = {
    ...vars,
    'skills': skills,
    'agents': agents,
    'has_skills': skills.isNotEmpty,
    'has_agents': agents.isNotEmpty,
    'claude_settings_json': _json.convert({
      'extraKnownMarketplaces': {
        marketplace: {'source': 'github', 'repo': marketplace},
      },
      'enabledPlugins': {
        for (final plugin in vgvPlugins) '$plugin@$marketplace': true,
      },
    }),
    'gemini_settings_json': _json.convert({
      'context': {'fileName': 'AGENTS.md'},
      'mcpServers': mcpServers,
    }),
    'opencode_config_json': _json.convert({
      r'$schema': 'https://opencode.ai/config.json',
      'mcp': _toOpenCode(mcpServers),
      'instructions': ['AGENTS.md'],
    }),
    'pi_settings_json': _json.convert({
      'skills': [skillsRoot],
    }),
    'codex_config_toml': _toCodexToml(mcpServers),
  };
}

/// OpenCode merges command and args into a single array and types each server.
Map<String, dynamic> _toOpenCode(Map<String, Map<String, dynamic>> servers) {
  return servers.map((name, server) {
    final url = server['url'];
    if (url is String) {
      return MapEntry(name, <String, dynamic>{'type': 'remote', 'url': url});
    }
    return MapEntry(name, <String, dynamic>{
      'type': 'local',
      'command': <String>[
        server['command'] as String? ?? '',
        ...(server['args'] as List? ?? const []).cast<String>(),
      ],
      if (server['env'] case final Map<dynamic, dynamic> env
          when env.isNotEmpty)
        'environment': env,
    });
  });
}

/// Codex declares servers as `[mcp_servers.<name>]` tables in TOML.
String _toCodexToml(Map<String, Map<String, dynamic>> servers) {
  if (servers.isEmpty) return '# No MCP servers were resolved.';
  final buffer = StringBuffer();
  for (final MapEntry(key: name, value: server) in servers.entries) {
    buffer.writeln('[mcp_servers.$name]');
    final url = server['url'];
    if (url is String) {
      buffer.writeln('url = ${jsonEncode(url)}');
    } else {
      buffer.writeln('command = ${jsonEncode(server['command'])}');
      final args = (server['args'] as List? ?? const []).cast<String>();
      if (args.isNotEmpty) buffer.writeln('args = ${jsonEncode(args)}');
    }
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<dynamic, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();
}

Map<String, Map<String, dynamic>> _mapOfMaps(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in value.entries)
      if (value is Map) '$key': Map<String, dynamic>.from(value),
  };
}
