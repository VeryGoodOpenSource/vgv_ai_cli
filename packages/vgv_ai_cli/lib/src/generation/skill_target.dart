import 'package:path/path.dart' as p;

/// The `skills_root`-relative location a plugin's skill is materialized to.
///
/// Skills are namespaced under their plugin so two plugins can ship a skill of
/// the same name without colliding, matching the lockfile's `target` field
/// (for example `vgv-wingspan/plan`). [source] is the skill's repo-relative
/// directory (for example `skills/plan`); only its basename is used.
String skillTarget({required String plugin, required String source}) =>
    p.posix.join(plugin, p.basename(source));

/// The canonical on-disk path a plugin's skill is materialized to.
///
/// Joins [skillsRoot] with [skillTarget]. Posix separators are kept because the
/// path is surfaced verbatim in `AGENTS.md` and typically carries a leading
/// `~`.
String skillCanonicalPath({
  required String skillsRoot,
  required String plugin,
  required String source,
}) => p.posix.join(skillsRoot, skillTarget(plugin: plugin, source: source));
