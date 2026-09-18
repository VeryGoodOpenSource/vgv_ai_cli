import 'dart:convert';

import 'package:hooks/models/models.dart';

/// {@template agents_configuration}
/// The rendered configuration the `agents` templates render against.
///
/// The settings fragments are built here rather than in mustache. A template
/// loop cannot know which iteration is last, so it cannot place separators
/// correctly, and any JSON or TOML it produced would have to be re-indented
/// anyway. [toVars] serializes each settings model into the string vars the
/// fragments consume.
/// {@endtemplate}
class const AgentsConfiguration({
  required final List<Skill> skills,
  required final List<Agent> agents,
  required final ClaudeSettings claudeSettings,
  required final GeminiSettings geminiSettings,
  required final OpenCodeConfig openCodeConfig,
  required final PiSettings piSettings,
  required final CodexConfig codexConfig,
  final JsonEncoder encoder = const JsonEncoder.withIndent('  '),
}) {
  /// Whether any skills were resolved.
  bool get hasSkills => skills.isNotEmpty;

  /// Whether any agents were resolved.
  bool get hasAgents => agents.isNotEmpty;

  /// The template vars this configuration contributes.
  Map<String, dynamic> toVars() => <String, dynamic>{
    'skills': [for (final skill in skills) skill.toJson()],
    'agents': [for (final agent in agents) agent.toJson()],
    'has_skills': hasSkills,
    'has_agents': hasAgents,
    'claude_settings_json': encoder.convert(claudeSettings.toJson()),
    'gemini_settings_json': encoder.convert(geminiSettings.toJson()),
    'opencode_config_json': encoder.convert(openCodeConfig.toJson()),
    'pi_settings_json': encoder.convert(piSettings.toJson()),
    'codex_config_toml': codexConfig.toToml(),
  };
}
