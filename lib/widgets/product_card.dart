import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/theme.dart';
import '../data/analytics_binding.dart';
import '../data/models.dart';
import '../screens/product_detail_screen.dart';
import '../state/app_state.dart';

/// 商品卡（移动端横向封面档，参照 Web 的 <sm 档：封面 118px、卖家说明隐藏）。
/// - 曝光判据是「40% 可见一次」，不许改成「渲染即曝光」（§8.9）。
/// - null 不折 0：sku/lead_time/rating 的 null 各有画法（§6.2）。
/// - 推广标注只画出参给的 is_promoted，绝不自己按 pool 推断（§6.2、§9.5）。
class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.card,
    required this.source,
    required this.view,
    required this.position,
    required this.pageNumber,
    this.disabled = false,
    this.onDisabledTap,
  });

  final MarketCard card;
  final String source; // home|search|category|seller|related|detail
  final String view; // 客户端去重键（q|category|sort|page），不是持久判别字段
  final int position;
  final int pageNumber;
  final bool disabled; // 收藏里已下架的行：不可点的卡片，不是指向 404 的链接
  final VoidCallback? onDisabledTap;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _impressionSent = false;

  void _maybeImpression(AppState app) {
    if (_impressionSent || widget.disabled) return;
    if (!app.analytics.shouldCountImpression(source: widget.source, view: widget.view, position: widget.position, slug: widget.card.slug)) return;
    _impressionSent = true;
    app.analytics.track(AnalyticsBinding.impression(widget.card, source: widget.source, position: widget.position, page: widget.pageNumber, view: widget.view));
  }

  Future<void> _open(BuildContext context) async {
    if (widget.disabled) {
      widget.onDisabledTap?.call();
      return;
    }
    final app = context.read<AppState>();
    // 点击事件先入队并立即冲刷：App 里导航不销毁进程，但页面会被回收，规则照抄（§8.9）。
    app.analytics.track(AnalyticsBinding.cardClick(widget.card, source: widget.source, position: widget.position, page: widget.pageNumber, view: widget.view));
    unawaitedFlush(app);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductDetailScreen(slug: widget.card.slug),
    ));
  }

  void unawaitedFlush(AppState app) {
    app.analytics.flush();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.l10n;
    final c = widget.card;

    return VisibilityDetector(
      key: ValueKey('imp-${widget.source}-${widget.view}-${widget.position}-${c.slug}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        if (info.visibleFraction >= 0.4) _maybeImpression(app);
      },
      child: Material(
        color: MarketTokens.surface,
        borderRadius: BorderRadius.circular(MarketTokens.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(MarketTokens.radius),
          onTap: () => _open(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MarketTokens.radius),
              border: Border.all(color: MarketTokens.line),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(card: c),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (c.isPromoted) ...[
                            _PromoBadge(label: l.raw('promoted_badge')),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          _FavoriteButton(slug: c.slug),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(c.sellerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
                      const SizedBox(height: 4),
                      Text(formatPrice(c.priceUkr, c.currencySymbol), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: MarketTokens.primary, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      // 次级元信息行：≤390px 允许截断的是这一行，不是主价格与主 CTA（§9.6）。
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(c.inStock ? l.raw('in_stock') : l.raw('out_of_stock'), style: Theme.of(context).textTheme.bodySmall?.apply(color: c.inStock ? MarketTokens.success : MarketTokens.muted)),
                          // sku 为 null：这一格整行不出现，不打印空串
                          if (c.sku != null) Text(c.sku!, style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
                          // lead_time 为 null 时首页卡片留空（详情页才允许「未标注」）
                          if (c.leadTimeDays != null) Text(l.fill('lead_time', {'n': c.leadTimeDays})),
                          if (c.rating != null) Text('★ ${c.rating!.toStringAsFixed(1)}'), // null 不打成 0 分
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});
  final MarketCard card;

  @override
  Widget build(BuildContext context) {
    const size = 118.0;
    final url = card.imageUrl;
    if (url == null || card.imageCount == 0) {
      // 「无图卡片」是设计里存在的一档（§8.5），必须有占位样式。
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: MarketTokens.surfaceDim, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.image_outlined, color: MarketTokens.muted),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, width: size, height: size, errorWidget: (_, __, ___) => Container(color: MarketTokens.surfaceDim)),
          ),
          if (card.imageCount > 1)
            // /N 的分母是 image_count（服务端给的数），不是数组长度（§8.5）。
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text('/${card.imageCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFFFF1DE), borderRadius: BorderRadius.circular(6), border: Border.all(color: MarketTokens.promo.withValues(alpha: 0.4))),
      child: Text(label, style: const TextStyle(fontSize: 11, color: MarketTokens.promo, fontWeight: FontWeight.w700)),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Selector<AppState, bool>(
      shouldRebuild: (a, b) => a != b,
      selector: (_, s) => s.isFavorite(slug),
      builder: (context, favorited, __) {
        return IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(favorited ? Icons.favorite : Icons.favorite_border, color: favorited ? MarketTokens.primary : MarketTokens.muted),
          onPressed: () async {
            final message = await app.toggleFavorite(slug);
            if (message != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }
          },
        );
      },
    );
  }
}
