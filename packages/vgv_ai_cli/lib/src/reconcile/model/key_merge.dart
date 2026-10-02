import 'package:vgv_ai_cli/src/reconcile/model/deep_merge.dart';

/// {@template key_merge}
/// What merging VGV's value for one key into the user's table did.
/// {@endtemplate}
class const KeyMerge._({
  /// Whether the key now holds [value], rather than the user's value kept.
  required final bool writes,

  /// What the key holds once merged, when it [writes].
  required final Object? value,

  /// Whether the merge added something the table lacked at the key.
  required final bool adds,

  /// What the merge added, when it [adds]: the whole value of a new key, the
  /// keys a table gained, or the entries a list gained.
  required final Object? added,

  /// Whether the merge kept a value the user set in place of VGV's.
  required final bool declined,
}) {
  /// {@macro key_merge}
  ///
  /// The table lacked the key, so all of [value] is new.
  const new added(Object? value)
    : this._(
        writes: true,
        value: value,
        adds: true,
        added: value,
        declined: false,
      );

  /// {@macro key_merge}
  ///
  /// [value] is written over what the key held, adding nothing new.
  const new replaced(Object? value)
    : this._(
        writes: true,
        value: value,
        adds: false,
        added: null,
        declined: false,
      );

  /// {@macro key_merge}
  ///
  /// The key holds a table that [inner] merged VGV's table into.
  new table(DeepMerge inner)
    : this._(
        writes: true,
        value: inner.merged,
        adds: inner.added.isNotEmpty,
        added: inner.added,
        declined: inner.declined,
      );

  /// {@macro key_merge}
  ///
  /// The key holds the user's [existing] list with [gained] appended.
  new union(List<dynamic> existing, List<dynamic> gained)
    : this._(
        writes: true,
        value: <dynamic>[...existing, ...gained],
        adds: gained.isNotEmpty,
        added: gained,
        declined: false,
      );

  /// {@macro key_merge}
  ///
  /// The user's value is kept. It [declined] VGV's when the two differ.
  const new kept({required bool declined})
    : this._(
        writes: false,
        value: null,
        adds: false,
        added: null,
        declined: declined,
      );
}
