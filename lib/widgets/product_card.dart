import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../core/theme.dart';
import '../data/analytics_binding.dart';
import '../data/models.dart';
import '../screens/product_detail_screen.dart';
import '../state/app_state.dart';

/// 商品卡：微信小店式双列大图卡（业主 2026-10-31 决定，替代文档 §8.8 的单列档）。
/// 图占卡的绝对主角，文字只剩「标题两行 + 红价 + 一行灰字」；
/// 但服务端契约的渲染纪律一条不动：
/// - null 不折 0：sku/rating/lead_time 的 null 各有画法（§6.2）。
/// - 推广标注只画出参给的 is_promoted，显式排序不摘标（§6.2、§9.5）。
/// - /N 的分母是 image_count；无图是一档诚实的形态，必须有占位（§8.5）。
/// - 曝光判据是「40% 可见一次」，不许改成渲染即曝光（§8.9）。
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
  final String source;
  final String view;
  final int position;
  final int pageNumber;
  final bool disabled;
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
    app.analytics.track(AnalyticsBinding.cardClick(widget.card, source: widget.source, position: widget.position, page: widget.pageNumber, view: widget.view));
    app.analytics.flush();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductDetailScreen(slug: widget.card.slug, fromSource: widget.source),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = widget.card;

    return VisibilityDetector(
      key: ValueKey('imp-${widget.source}-${widget.view}-${widget.position}-${c.slug}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        if (info.visibleFraction >= 0.4) _maybeImpression(app);
      },
      child: Material(
        color: MarketTokens.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MarketTokens.line.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(card: c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题两行为限；推广披露在图上，不在这里。
                        Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600, color: MarketTokens.ink)),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(formatPrice(c.priceUkr, c.currencySymbol), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: MarketTokens.primary, height: 1.1)),
                            ),
                            // rating null 不打一颗空星（§6.2）；有值才出现。
                            if (c.rating != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 1),
                                child: Text('★${c.rating!.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: MarketTokens.muted)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // 一行灰字：卖家为主，次要元信息（起订/无货）跟在后面，窄屏截的是这一行（§9.6）。
                        Row(
                          children: [
                            if (!c.inStock) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(border: Border.all(color: MarketTokens.muted), borderRadius: BorderRadius.circular(3)),
                                child: Text(app.l10n.raw('out_of_stock'), style: const TextStyle(fontSize: 10, color: MarketTokens.muted)),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                c.sellerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: MarketTokens.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
    final app = context.read<AppState>();
    final url = card.imageUrl;
    return AspectRatio(
      aspectRatio: 0.8, // 4:5 竖图（业主 2026-10-31 决定，贴微信小店竖卡）
      child: Container(
        color: MarketTokens.surfaceDim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && card.imageCount > 0)
              CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Center(child: Icon(Icons.image_outlined, color: MarketTokens.muted)))
            else
              const Center(child: Icon(Icons.image_outlined, size: 30, color: MarketTokens.muted)),
            if (card.isPromoted)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4)),
                  child: Text(app.l10n.raw('promoted_badge'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ),
            // 收藏浮标：小号、半透明圆底，不抢图。
            Positioned(
              right: 4,
              top: 4,
              child: _FavoriteButton(slug: card.slug),
            ),
            if (card.imageCount > 1)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
                  child: Text('/${card.imageCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
          ],
        ),
      ),
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
      selector: (_, s) => s.isFavorite(slug),
      builder: (context, favorited, __) {
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final message = await app.toggleFavorite(slug);
            if (message != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: favorited ? 0.35 : 0.25), shape: BoxShape.circle),
              child: Icon(favorited ? Icons.favorite : Icons.favorite_border, size: 16, color: favorited ? MarketTokens.primary : Colors.white),
            ),
          ),
        );
      },
    );
  }
}

/// 双列网格的纵高：封面 4:5 + 文字区 84。宽度由调用方 LayoutBuilder 给出。
double gridMainAxisExtent(double crossColumnWidth) => crossColumnWidth * 1.25 + 84;
