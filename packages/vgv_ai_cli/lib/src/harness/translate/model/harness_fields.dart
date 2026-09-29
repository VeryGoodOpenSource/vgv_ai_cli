import 'package:equatable/equatable.dart';

/// {@template harness_fields}
/// What one harness's brick template renders an agent or a command with,
/// on top of the name, instructions and body every harness shares.
///
/// Each field is finished text the brick places as written, and null when
/// the harness's template does not read it.
/// {@endtemplate}
class const HarnessFields({
  /// The frontmatter a markdown agent or command opens with.
  final String? frontmatter,

  /// The whole TOML document of an agent or command.
  final String? toml,
}) extends Equatable {
  /// The fields keyed as the brick reads them, leaving out every null one.
  Map<String, String> toMap() => {'frontmatter': ?frontmatter, 'toml': ?toml};

  @override
  List<Object?> get props => [frontmatter, toml];
}
