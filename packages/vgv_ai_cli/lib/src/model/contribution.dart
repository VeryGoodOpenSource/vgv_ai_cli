import 'package:collection/collection.dart';
import 'package:vgv_ai_cli/src/model/drift.dart';
import 'package:vgv_ai_cli/src/model/subtraction.dart';

/// {@template contribution}
/// The part of a merged document that is VGV's, shaped like the document:
/// the keys VGV added with the values it wrote, and the entries it appended
/// to lists the user already had. Nothing the user wrote first is in it.
///
/// Install records one, doctor compares it with the document and uninstall
/// subtracts it, all through the methods here, so the three cannot disagree
/// about what VGV owns.
/// {@endtemplate}
extension type const Contribution(Map<String, dynamic> keys) {
  /// {@macro contribution}
  ///
  /// What of [written] is VGV's, given the document was [before] and VGV
  /// last contributed [managed].
  ///
  /// A key is VGV's when it is new, or when VGV contributed it and the user
  /// has not changed it since. Otherwise VGV owns only the entries it added
  /// to a list and what it owns inside a table.
  new of(
    Map<String, dynamic> before,
    Map<String, dynamic> written,
    Contribution managed,
  ) : this(_of(before, written, managed));

  /// A contribution with nothing in it.
  static const none = Contribution({});

  /// Whether nothing in the document is VGV's.
  bool get isEmpty => keys.isEmpty;

  /// The contribution as it is written to the manifest.
  Map<String, dynamic> toJson() => keys;

  /// Whether VGV contributed [key] whole, as [current], and it is untouched.
  bool owns(String key, Object? current) =>
      keys.containsKey(key) && _deep.equals(keys[key], current);

  /// What of this [current] no longer holds, and what it holds changed.
  ///
  /// A list is missing when any entry VGV appended is gone. Entries the user
  /// added beside VGV's are theirs and do not count.
  Drift compare(Map<String, dynamic> current) {
    final missing = <String>[];
    final drifted = <String>[];

    void compare(
      Map<String, dynamic> ours,
      Map<String, dynamic> now,
      List<String> path,
    ) {
      for (final MapEntry(:key, :value) in ours.entries) {
        final keyPath = [...path, key];
        if (!now.containsKey(key)) {
          missing.add(keyPath.join('.'));
          continue;
        }

        switch ((value, now[key])) {
          case (
            final Map<String, dynamic> ours,
            final Map<String, dynamic> now,
          ):
            compare(ours, now, keyPath);
          case (final List<dynamic> ours, final List<dynamic> now):
            if (!ours.every((item) => _contains(now, item))) {
              missing.add(keyPath.join('.'));
            }
          case (final ours, final now) when !_deep.equals(ours, now):
            drifted.add(keyPath.join('.'));
        }
      }
    }

    compare(keys, current, const []);
    return Drift(missing: missing, drifted: drifted);
  }

  /// [current] without what is VGV's, and whether any of it was kept.
  ///
  /// A value VGV wrote that the user has changed is kept, and reported as
  /// kept, unless forced. A table or list left empty goes with it.
  Subtraction subtract(Map<String, dynamic> current, {required bool force}) {
    final result = {...current};
    var kept = false;

    for (final MapEntry(:key, :value) in keys.entries) {
      if (!result.containsKey(key)) continue;

      final inner = _subtract(result[key], value, force: force);
      kept = kept || inner.kept;
      if (inner.remaining
          case null || Map(isEmpty: true) || List(isEmpty: true)) {
        result.remove(key);
      } else {
        result[key] = inner.remaining;
      }
    }
    return Subtraction(remaining: result, kept: kept);
  }
}

const _deep = DeepCollectionEquality();

/// Whether [list] holds a value structurally equal to [item].
bool _contains(List<dynamic> list, Object? item) =>
    list.any((entry) => _deep.equals(entry, item));

Map<String, dynamic> _of(
  Map<String, dynamic> before,
  Map<String, dynamic> written,
  Contribution managed,
) {
  final owned = <String, dynamic>{};
  for (final MapEntry(:key, :value) in written.entries) {
    final prior = before[key];
    final mine = managed.keys[key];
    if (!before.containsKey(key) || managed.owns(key, prior)) {
      owned[key] = value;
      continue;
    }

    final part = switch ((prior, value)) {
      (final Map<String, dynamic> prior, final Map<String, dynamic> value) =>
        _of(
          prior,
          value,
          mine is Map<String, dynamic> ? Contribution(mine) : Contribution.none,
        ),
      (final List<dynamic> prior, final List<dynamic> value) => [
        for (final item in value)
          if (!_contains(prior, item) ||
              (mine is List && _contains(mine, item)))
            item,
      ],
      _ => null,
    };
    if (part case Map(isNotEmpty: true) || List(isNotEmpty: true)) {
      owned[key] = part;
    }
  }
  return owned;
}

/// What is left of [now] once [ours] is taken out of it, or null when
/// nothing is.
_Subtracted _subtract(Object? now, Object? ours, {required bool force}) =>
    switch ((now, ours)) {
      (final Map<String, dynamic> now, final Map<String, dynamic> ours) =>
        switch (Contribution(ours).subtract(now, force: force)) {
          Subtraction(:final remaining, :final kept) => _Subtracted(
            remaining: remaining,
            kept: kept,
          ),
        },
      (final List<dynamic> now, final List<dynamic> ours) => _Subtracted(
        remaining: [
          for (final item in now)
            if (!_contains(ours, item)) item,
        ],
        kept: false,
      ),
      _ when force || _deep.equals(now, ours) => const _Subtracted(
        remaining: null,
        kept: false,
      ),
      _ => _Subtracted(remaining: now, kept: true),
    };

/// One value with VGV's part taken out, or null when all of it was VGV's.
class const _Subtracted({
  required final Object? remaining,
  required final bool kept,
});
