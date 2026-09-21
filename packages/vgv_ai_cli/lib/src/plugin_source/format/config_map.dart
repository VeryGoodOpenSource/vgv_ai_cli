/// {@template config_map}
/// A tolerant view over a decoded configuration map.
///
/// Plugin files arrive as YAML frontmatter, hooks JSON and MCP JSON. Every
/// accessor tolerates a missing or wrong-typed value, returning null or empty
/// rather than throwing, and holds no harness- or format-specific knowledge.
/// {@endtemplate}
class const ConfigMap._(final Map<String, Object?> values) {
  /// Wraps [source] after normalizing YAML/JSON into plain Dart collections, so
  /// consumers only ever see `Map<String, Object?>` and `List<Object?>`. A
  /// [source] that is not a map yields an empty view.
  ///
  /// This is the only way to build a [ConfigMap]: the accessors match on the
  /// normalized types, so a view over an un-normalized map returns nothing.
  factory of(Object? source) => ConfigMap._(_normalizeMap(source));

  /// The raw value under [key], or `null` when absent.
  Object? operator [](String key) => values[key];

  /// Every key/value pair, for callers that iterate an open-ended map such as
  /// the hooks event map or the MCP server map.
  Iterable<MapEntry<String, Object?>> get entries => values.entries;

  /// The value under [key] stringified, or `null` when absent.
  String? string(String key) {
    final value = values[key];
    return value == null ? null : '$value';
  }

  /// The value under [key] when it is an `int`, else `null`.
  int? integer(String key) {
    final value = values[key];
    return value is int ? value : null;
  }

  /// The value under [key] when it is a `bool`, else `null`.
  bool? boolean(String key) {
    final value = values[key];
    return value is bool ? value : null;
  }

  /// The value under [key] as a list of non-blank strings.
  ///
  /// A list is taken element-wise; any other scalar is split on commas. Both
  /// shapes appear in the plugins: `skills` is written both inline as `[a, b]`
  /// and as a block sequence, and a bare `skills: a` is one entry.
  List<String> stringList(String key) => switch (values[key]) {
    null => const [],
    final Iterable<Object?> items => [
      for (final item in items)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ],
    final value => [
      for (final item in '$value'.split(','))
        if (item.trim().isNotEmpty) item.trim(),
    ],
  };

  /// The value under [key] wrapped as a nested [ConfigMap], or `null` when it
  /// is absent or not a map.
  ConfigMap? child(String key) => switch (values[key]) {
    final Map<String, Object?> map => ConfigMap._(map),
    _ => null,
  };

  /// The maps within [value], each wrapped as a [ConfigMap].
  ///
  /// Non-map elements are dropped. Serves callers walking a list of records,
  /// such as hook registrations and the commands within one.
  static List<ConfigMap> maps(Object? value) => switch (value) {
    final List<Object?> items => [
      for (final item in items)
        if (item is Map<String, Object?>) ConfigMap._(item),
    ],
    _ => const [],
  };

  static Map<String, Object?> _normalizeMap(Object? source) => switch (source) {
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _normalize(entry.value),
    },
    _ => const {},
  };

  static Object? _normalize(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _normalize(entry.value),
    },
    // Match String explicitly so scalars pass through untouched.
    final String value => value,
    final Iterable<Object?> items => [
      for (final item in items) _normalize(item),
    ],
    _ => value,
  };
}
