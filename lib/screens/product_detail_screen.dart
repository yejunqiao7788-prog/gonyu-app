import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../data/analytics_binding.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/chat_panel.dart';
import '../widgets/common.dart';
import '../widgets/product_card.dart';
import 'auth_screen.dart';
import 'lead_form.dart';
import 'seller_screen.dart';

/// 详情页（§6.4）。这一支在服务端有两次 Promise.all，App 只发一次请求即可。
/// 三个 null 按句子画、不按 0 画：ttfr_hours / seller.listing_count / rating。
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.slug, this.fromSource = 'detail', this.openChat = false, this.chatToken});

  final String slug;
  final String fromSource; // 从哪来：home|search|category|seller|related（product_view 的 source）
  final bool openChat; // ?chat=open 的等价：继续已有线程，而不是开第二条（§8.6）
  final String? chatToken;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final AppState _app;
  MarketProductDetail? detail;
  MarketApiException? error;
  bool notFound = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final d = await _app.marketApi.getProduct(widget.slug, _app.lang);
      if (!mounted) return;
      setState(() {
        detail = d;
        error = null;
      });
      _app.analytics.track(AnalyticsBinding.productView(d.card, source: widget.fromSource));
      if (widget.openChat) _openChat();
    } on MarketApiException catch (e) {
      if (!mounted) return;
      // slug 不存在或行不在投影表 ⇒ 404 LISTING_NOT_FOUND：这是列表页可以合法点进来的
      // 终态，正确反应是「这个商品已经不在公域了」的整页态 + 回首页，而不是 toast（§6.4）。
      setState(() {
        notFound = e.code == 'LISTING_NOT_FOUND' || e.isNotFound;
        error = e;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openChat() async {
    final d = detail;
    if (d == null) return;
    // 硬登录门：门开着（现网即为开着）而未登录 → 先弹登录，不是让买家打完字再吃 401（§4.5、D2）。
    if (d.buyerGateEnabled && !_app.signedIn) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen(initialMode: 'login')));
      if (ok != true || !mounted) return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        builder: (ctx, _) => ChangeNotifierProvider.value(
          value: _app,
          child: ChatPanel(slug: d.card.slug, listingTitle: d.card.title, buyerGateEnabled: d.buyerGateEnabled, initialToken: widget.chatToken),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? null : IconButton(icon: const Icon(Icons.home), onPressed: () => Navigator.pop(context)),
        title: Text(detail?.card.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      // 客服只有一个面板实例、一个状态持有者；入口按钮收缩成图标由 aria 语义承担（§8.8）。
      bottomNavigationBar: detail == null ? null : _bottomDock(detail!),
      body: _body(),
    );
  }

  Widget _body() {
    if (loading && detail == null) return const SkeletonGrid(rows: 3);
    if (notFound) {
      return TerminalStatePage(message: _app.l10n.raw('detail_offline_title'), homeLabel: _app.l10n.raw('back_home'));
    }
    final e = error;
    if (e != null && detail == null) {
      // 读失败与「这条已下架」是两屏：前者可重试，后者不可（§10.3 第 8 行）。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_app.l10n.raw('detail_load_failed')),
            const SizedBox(height: 8),
            Text(_app.describeError(e) ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(onPressed: _load, child: Text(_app.l10n.raw('retry'))),
          ],
        ),
      );
    }
    final d = detail;
    if (d == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        _gallery(d),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.card.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(formatPrice(d.card.priceUkr, d.card.currencySymbol), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: MarketTokens.primary, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _tag(d.card.inStock ? _app.l10n.raw('in_stock') : _app.l10n.raw('out_of_stock'), strong: d.card.inStock),
                  if (d.card.minOrderQty != null) _tag(_app.l10n.fill('min_order', {'n': d.card.minOrderQty})),
                  // 详情页才允许显示「未标注」（首页卡片那一格留空，§6.2）
                  _tag(d.card.leadTimeDays != null ? _app.l10n.fill('lead_time', {'n': d.card.leadTimeDays}) : _app.l10n.raw('lead_time_unmarked')),
                  if (d.card.supportsOnlinePay) _tag(_app.l10n.raw('filter_online_pay')),
                  if (d.card.supportUk) _tag(_app.l10n.raw('support_uk')),
                  if (d.card.rating != null) _tag('★ ${d.card.rating!.toStringAsFixed(1)}'),
                ],
              ),
              // ttfr：≥24h 换成天（「3.5 天」比「72 h」好读），不足 1 小时显示 1 小时；
              // null 整行消失——写「0 小时内回复」等于替卖家承诺他没演示过的速度（§6.4）。
              if (d.ttfrHours != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    d.ttfrHours! >= 24
                        ? _app.l10n.fill('detail_reply_time_days', {'d': (d.ttfrHours! / 24).toStringAsFixed(1)})
                        : _app.l10n.fill('detail_reply_time', {'h': d.ttfrHours! < 1 ? 1 : d.ttfrHours!.ceil()}),
                    style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.success),
                  ),
                ),
              const SizedBox(height: 16),
              _sellerCard(d),
              if (d.description != null && d.description!.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(_app.l10n.raw('detail_description'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(d.description!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (d.specAttrs.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(_app.l10n.raw('detail_specs'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final entry in d.specAttrs.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(width: 130, child: Text(entry.key, style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted))),
                        Expanded(child: Text('${entry.value}', style: Theme.of(context).textTheme.bodyMedium)),
                      ],
                    ),
                  ),
              ],
              if (d.related.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(_app.l10n.raw('detail_related'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final r in d.related)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ProductCard(card: r, source: 'related', view: 'related|${d.card.slug}', position: d.related.indexOf(r), pageNumber: 1),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _gallery(MarketProductDetail d) {
    final urls = d.imageUrls;
    if (urls.isEmpty) {
      // image_count === 0 是诚实的值：整块隐藏或「暂无图片」，不显示空轮播（§10.3 第 4 行）。
      return Container(
        height: 220,
        color: MarketTokens.surfaceDim,
        child: Center(child: Text(_app.l10n.raw('images_absent'), style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted))),
      );
    }
    return SizedBox(
      height: 260,
      child: PageView.builder(
        itemCount: urls.length,
        itemBuilder: (_, i) => Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(imageUrl: urls[i], fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: MarketTokens.surfaceDim)),
            // /N 的分母是 image_count（服务端给的数），不是数组长度（§8.5）。
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                child: Text('${i + 1}/${d.card.imageCount}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sellerCard(MarketProductDetail d) {
    final s = d.seller;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MarketTokens.surface, borderRadius: BorderRadius.circular(MarketTokens.radius), border: Border.all(color: MarketTokens.line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(_app.l10n.raw('detail_seller_listings').split('{n}').first, style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
                    // listing_count 为 null：这一格没读到 → 画 —，绝不折成 0（§6.4、§7.8）。
                    if (s.listingCount == null)
                      NullDash(tooltip: _app.l10n.raw('not_loaded'))
                    else
                      Text('${s.listingCount}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          // 进店链接用 slug，不用店名拼 URL（§10.4 第 4 行）。
          OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SellerScreen(sellerSlug: s.slug))), child: Text(_app.l10n.raw('visit_seller'))),
        ],
      ),
    );
  }

  Widget _bottomDock(MarketProductDetail d) {
    return SafeArea(
      child: Container(
        // 吸底条偏移由自己发布的高度推导，不用像素常量：先测量再上报（§8.8）。
        key: const Key('buy-dock'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(color: MarketTokens.surface, border: Border(top: BorderSide(color: MarketTokens.line))),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                // 留资按钮保持完整标签——装不下时削的是次要信息，不是主 CTA 的名字（§9.6）。
                onPressed: () => showLeadForm(context, d),
                child: Text(_app.l10n.raw('cta_submit_lead')),
              ),
            ),
            if (d.chatEnabled) ...[
              const SizedBox(width: 10),
              IconButton.outlined(
                // 窄屏时客服入口收缩为图标（名字由 tooltip 承载，等价 web 的 aria-label）。
                tooltip: _app.l10n.raw('cta_chat'),
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: _openChat,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, {bool strong = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFE7F5EC) : MarketTokens.surfaceDim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: strong ? MarketTokens.success : MarketTokens.ink)),
    );
  }
}
