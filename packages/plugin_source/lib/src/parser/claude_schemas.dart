/// The shapes of the Claude Code plugin files, as far as the parser reads
/// them.
///
/// Each shape is an extension type over the decoded map: its schema says what
/// the file holds, and its getters read the values the schema has checked, so
/// the parser never casts. Each key the parser reads is typed, and a mismatch
/// throws. Keys it does not read pass through, so an upstream Claude addition
/// is not a broken file.
library;

import 'package:ack/ack.dart';
import 'package:plugin_source/src/format/format.dart';

/// `.claude-plugin/plugin.json`.
extension type PluginManifestJson(Map<String, Object?> _json) {
  /// Decodes and validates [source], read from the file at [path].
  factory decodeJson(String source, {required String path}) =>
      PluginManifestJson(_schema.decodeJson(source, path: path));

  static final ObjectSchema _schema = Ack.object({
    'name': Ack.string().optional(),
  }).passthrough();

  /// The plugin's name as the manifest declares it, or null when unset.
  String? get name => _json['name'] as String?;
}

/// `.mcp.json`.
extension type McpFileJson(Map<String, Object?> _json) {
  /// Decodes and validates [source], read from the file at [path].
  factory decodeJson(String source, {required String path}) =>
      McpFileJson(_schema.decodeJson(source, path: path));

  static final ObjectSchema _schema = Ack.object({
    'mcpServers': Ack.map(McpServerJson._schema).optional(),
  }).passthrough();

  /// Each server declaration, by the name it is declared under.
  Map<String, McpServerJson> get servers => {
    for (final MapEntry(:key, :value)
        in (_json['mcpServers'] as Map<String, Object?>? ?? const {}).entries)
      key: McpServerJson(value! as Map<String, Object?>),
  };
}

/// One server declaration in `.mcp.json`. A server with a `url` is remote,
/// one with a `command` is local.
extension type McpServerJson(Map<String, Object?> _json) {
  static final ObjectSchema _schema = Ack.object({
    'url': Ack.string().optional(),
    'headers': Ack.map(Ack.string()).optional(),
    'command': Ack.string().optional(),
    'args': Ack.list(Ack.string()).optional(),
    'env': Ack.map(Ack.string()).optional(),
  }).passthrough();

  /// The endpoint a remote server is reached at, or null for a local one.
  String? get url => _json['url'] as String?;

  /// Headers sent with each request to [url].
  Map<String, String> get headers => _strings(_json['headers']);

  /// The executable a local server launches, or null for a remote one.
  String? get command => _json['command'] as String?;

  /// Arguments passed to [command].
  List<String> get args => [...?_json['args'] as List<String>?];

  /// Environment variables set for the subprocess launched by [command].
  Map<String, String> get env => _strings(_json['env']);

  static Map<String, String> _strings(Object? block) =>
      Map.from(block as Map<String, Object?>? ?? const {});
}

/// `hooks/hooks.json`, and an agent's frontmatter, which declares the hooks
/// that fire while it runs in the same shape.
extension type HooksJson(Map<String, Object?> _json) {
  /// Validates [values], an already-decoded document from the file at [path].
  factory decode(Object? values, {required String path}) =>
      HooksJson(_schema.decode(values, path: path));

  /// Decodes and validates [source], read from the file at [path].
  factory decodeJson(String source, {required String path}) =>
      HooksJson(_schema.decodeJson(source, path: path));

  static final ObjectSchema _schema = Ack.object({
    'hooks': Ack.map(Ack.list(HookRegistrationJson._schema)).optional(),
  }).passthrough();

  /// The registrations under each event, or null when there is no `hooks`
  /// key.
  Map<String, List<HookRegistrationJson>>? get events =>
      switch (_json['hooks']) {
        final Map<String, Object?> events => {
          for (final MapEntry(:key, :value) in events.entries)
            key: [
              for (final registration in value! as List<Object?>)
                HookRegistrationJson(registration! as Map<String, Object?>),
            ],
        },
        _ => null,
      };
}

/// One registration under an event: the hooks it runs and the tools it
/// matches.
extension type HookRegistrationJson(Map<String, Object?> _json) {
  static final ObjectSchema _schema = Ack.object({
    'matcher': Ack.string().optional(),
    'hooks': Ack.list(HookJson._schema),
  }).passthrough();

  /// Which tools this registration fires for, or null for every tool.
  String? get matcher => _json['matcher'] as String?;

  /// The hooks this registration runs.
  List<HookJson> get hooks => [
    for (final hook in _json['hooks']! as List<Object?>)
      HookJson(hook! as Map<String, Object?>),
  ];
}

/// One hook in a registration. A hook without a `command`, such as a `prompt`
/// hook, runs nothing a harness can translate.
extension type HookJson(Map<String, Object?> _json) {
  static final ObjectSchema _schema = Ack.object({
    'type': Ack.string().optional(),
    'command': Ack.string().optional(),
    'timeout': Ack.integer().optional(),
  }).passthrough();

  /// The hook's kind, such as `command`.
  String? get type => _json['type'] as String?;

  /// The shell command this hook runs, or null when it runs nothing
  /// translatable.
  String? get command => _json['command'] as String?;

  /// How long the command may run, or null for no limit.
  int? get timeout => _json['timeout'] as int?;
}

/// A skill's `SKILL.md` frontmatter, validated for the keys Claude adds
/// beyond the ones every format shares.
///
/// Built only through its `decode` factory, so holding one means its keys
/// were validated.
extension type SkillFrontmatter._(Frontmatter _frontmatter)
    implements Frontmatter {
  /// Validates [frontmatter], read from the file at [path].
  ///
  /// The decoded map is discarded: decoding moves the declared keys ahead of
  /// the rest, which would reorder the portable frontmatter written for every
  /// harness. The schema neither coerces nor defaults, so [values] holds
  /// exactly what it checked.
  factory decode(Frontmatter frontmatter, {required String path}) {
    _schema.decode(frontmatter.values, path: path);
    return SkillFrontmatter._(frontmatter);
  }

  static final ObjectSchema _schema = Ack.object({
    'user-invocable': Ack.boolean().optional(),
    'allowed-tools': Ack.string().optional(),
    'tools': Ack.string().optional(),
    'when_to_use': Ack.string().optional(),
  }).passthrough();

  /// Whether a user can invoke the skill as a command, or `null` when the
  /// `user-invocable` key is absent.
  bool? get userInvocable => values['user-invocable'] as bool?;

  /// The `allowed-tools` value, tool names separated by spaces or commas.
  String? get allowedTools => values['allowed-tools'] as String?;

  /// The `tools` value, which some skills write in place of
  /// `allowed-tools`.
  String? get tools => values['tools'] as String?;

  /// Claude's own key for the skill's trigger phrases, flattened onto one
  /// line, or `null` when absent.
  String? get whenToUse =>
      Frontmatter.oneLine(values['when_to_use'] as String?);
}
