/// Deep-merges the VGV-owned [overlay] onto the user's [base] map.
///
/// Maps are merged recursively so nested user-owned keys survive. On any other
/// conflict the [overlay] (VGV) value wins, because those keys are the ones the
/// CLI manages. Lists are treated as leaves and replaced wholesale rather than
/// concatenated, which keeps managed arrays (for example `instructions`)
/// deterministic instead of accumulating duplicates across re-runs.
Map<String, dynamic> deepMergeJson(
  Map<String, dynamic> base,
  Map<String, dynamic> overlay,
) {
  final result = Map<String, dynamic>.from(base);
  for (final MapEntry(:key, :value) in overlay.entries) {
    final existing = result[key];
    if (existing is Map && value is Map) {
      result[key] = deepMergeJson(
        Map<String, dynamic>.from(existing),
        Map<String, dynamic>.from(value),
      );
    } else {
      result[key] = value;
    }
  }
  return result;
}
