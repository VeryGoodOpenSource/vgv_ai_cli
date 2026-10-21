/// {@template section_span}
/// Where a section VGV manages starts and ends in a markdown file, markers
/// included.
/// {@endtemplate}
class const SectionSpan({
  /// The offset of the section's start marker.
  required final int start,

  /// The offset just past the section's end marker.
  required final int end,
}) {
  /// {@macro section_span}
  this;
}
