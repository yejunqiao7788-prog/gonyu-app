import 'market_api.dart';
import 'models.dart';

/// 事件构造器：把卡片折成埋点行。只带 slug/position/source/query/sort——
/// 卖家与类目 id 由服务端解析；slot_kind、买家标识、号码一律不发（§6.9、§7.6、§7.7）。
class AnalyticsBinding {
  static MarketEventRow impression(
    MarketCard card, {
    required String source,
    required int position,
    required int page,
    required String view,
  }) =>
      MarketEventRow(type: 'impression', listingSlug: card.slug, sellerSlug: card.sellerSlug, source: source, position: position, page: page);

  static MarketEventRow cardClick(
    MarketCard card, {
    required String source,
    required int position,
    required int page,
    required String view,
  }) =>
      MarketEventRow(type: 'card_click', listingSlug: card.slug, sellerSlug: card.sellerSlug, source: source, position: position, page: page);

  static MarketEventRow productView(MarketCard card, {required String source}) =>
      MarketEventRow(type: 'product_view', listingSlug: card.slug, sellerSlug: card.sellerSlug, source: source);

  static MarketEventRow leadFormOpen(String slug) => MarketEventRow(type: 'lead_form_open', listingSlug: slug);

  static MarketEventRow leadFormSubmit(String slug) => MarketEventRow(type: 'lead_form_submit', listingSlug: slug);

  static MarketEventRow chatOpen(String slug) => MarketEventRow(type: 'chat_open', listingSlug: slug);
}
