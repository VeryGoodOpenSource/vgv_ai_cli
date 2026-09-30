/// The rules for what of a merged document is VGV's.
///
/// A contribution is shaped like the document: the keys VGV added with the
/// values it wrote, and the entries it appended to lists the user already
/// had. Install records one, doctor compares it with the document and
/// uninstall subtracts it, all through the functions here, so the three
/// cannot disagree about what VGV owns.
library;

import 'package:vgv_ai_cli/src/document/documents.dart';

/// Whether VGV contributed [key] whole, as [current], and it is untouched.
bool isManaged(Map<String, dynamic> managed, String key, Object? current) =>
    managed.containsKey(key) && deepEquality.equals(managed[key], current);

/// What of [written] is VGV's, given the document was [before] and VGV
/// last contributed [managed].
///
/// A key is VGV's when it is new, or when VGV contributed it and the user
/// has not changed it since. Otherwise VGV owns only the entries it added
/// to a list and what it owns inside a table.
Map<String, dynamic> contributionOf(
  Map<String, dynamic> before,
  Map<String, dynamic> written,
  Map<String, dynamic> managed,
) {
  final owned = <String, dynamic>{};
  for (final MapEntry(:key, :value) in written.entries) {
    final prior = before[key];
    final mine = managed[key];
    if (!before.containsKey(key) || isManaged(managed, key, prior)) {
      owned[key] = value;
      continue;
    }

    final part = switch ((prior, value)) {
      (final Map<String, dynamic> prior, final Map<String, dynamic> value) =>
        contributionOf(prior, value, mine is Map<String, dynamic> ? mine : {}),
      (final List<dynamic> prior, final List<dynamic> value) => [
        for (final item in value)
          if (!listContains(prior, item) ||
              (mine is List && listContains(mine, item)))
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

/// The dotted key paths of [contribution] that [current] no longer holds,
/// and those it holds with a different value.
///
/// A list is missing when any entry VGV appended is gone. Entries the user
/// added beside VGV's are theirs and do not count.
({List<String> missing, List<String> drifted}) compareContribution(
  Map<String, dynamic> contribution,
  Map<String, dynamic> current,
) {
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
        case (final Map<String, dynamic> ours, final Map<String, dynamic> now):
          compare(ours, now, keyPath);
        case (final List<dynamic> ours, final List<dynamic> now):
          if (!ours.every((item) => listContains(now, item))) {
            missing.add(keyPath.join('.'));
          }
        case (final ours, final now) when !deepEquality.equals(ours, now):
          drifted.add(keyPath.join('.'));
      }
    }
  }

  compare(contribution, current, const []);
  return (missing: missing, drifted: drifted);
}

/// [current] without what [contribution] says is VGV's, and whether any of
/// it was kept.
///
/// A value VGV wrote that the user has changed is kept, and reported as
/// kept, unless forced. A table or list left empty goes with it.
({Map<String, dynamic> remaining, bool kept}) subtractContribution(
  Map<String, dynamic> current,
  Map<String, dynamic> contribution, {
  required bool force,
}) {
  final result = {...current};
  var kept = false;

  for (final MapEntry(:key, :value) in contribution.entries) {
    if (!result.containsKey(key)) continue;

    final inner = _subtractValue(result[key], value, force: force);
    kept = kept || inner.kept;
    if (inner.remaining
        case null || Map(isEmpty: true) || List(isEmpty: true)) {
      result.remove(key);
    } else {
      result[key] = inner.remaining;
    }
  }
  return (remaining: result, kept: kept);
}

/// What is left of [now] once [ours] is taken out of it, or null when
/// nothing is.
({Object? remaining, bool kept}) _subtractValue(
  Object? now,
  Object? ours, {
  required bool force,
}) => switch ((now, ours)) {
  (final Map<String, dynamic> now, final Map<String, dynamic> ours) =>
    subtractContribution(now, ours, force: force),
  (final List<dynamic> now, final List<dynamic> ours) => (
    remaining: [
      for (final item in now)
        if (!listContains(ours, item)) item,
    ],
    kept: false,
  ),
  _ when force || deepEquality.equals(now, ours) => (
    remaining: null,
    kept: false,
  ),
  _ => (remaining: now, kept: true),
};
