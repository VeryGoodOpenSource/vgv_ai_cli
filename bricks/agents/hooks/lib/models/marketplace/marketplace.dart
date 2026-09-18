import 'package:json_annotation/json_annotation.dart';

part 'marketplace.g.dart';

/// {@template marketplace}
/// A Claude Code marketplace that hosts the VGV plugins.
///
/// [repo] is the `owner/name` slug of the GitHub repository backing the
/// marketplace. It doubles as the key Claude Code stores the marketplace under.
/// {@endtemplate}
@JsonSerializable(createFactory: false)
class const Marketplace(final String repo, {final String source = 'github'}) {
  /// The Very Good Ventures marketplace hosting the VGV plugins.
  const new veryGood()
    : this('VeryGoodOpenSource/very_good_claude_marketplace');

  /// Serializes the marketplace as Claude Code expects it under
  /// `extraKnownMarketplaces`.
  Map<String, dynamic> toJson() => _$MarketplaceToJson(this);
}
