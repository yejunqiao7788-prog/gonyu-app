import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/l10n.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/product_card.dart';

/// 店铺页（§6.5）。默认流 ≠ 店铺页：这一面不隐藏 muted，买家从首页看到 1 条、
/// 进店看到 2 条都是对的——两个页面各读各的端点，不共享缓存键。
class SellerScreen extends StatefulWidget {
  const SellerScreen({super.key, required this.sellerSlug});
  final String sellerSlug;

  @override
  State<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends State<SellerScreen> {
  late final AppState _app;
  String sellerName = '';
  final List<MarketCard> items = [];
  int total = 0;
  int pageSize = 24;
  int _loadedPages = 0;
  bool loading = true;
  bool loadingMore = false;
  MarketApiException? error;
  bool inStockOnly = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) _loadNext();
  }

  MarketL10n get _l => _app.l10n;

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final page = await _app.marketApi.getSellerProducts(widget.sellerSlug, page: 1, pageSize: pageSize, inStock: inStockOnly ? true : null, lang: _app.lang);
      setState(() {
        sellerName = page.sellerName;
        items
          ..clear()
          ..addAll(page.items);
        total = page.total;
        _loadedPages = page.page;
        error = null;
      });
    } on MarketApiException catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadNext() async {
    if (loadingMore || loading || _loadedPages * pageSize >= total) return;
    setState(() => loadingMore = true);
    try {
      final next = await _app.marketApi.getSellerProducts(widget.sellerSlug, page: _loadedPages + 1, pageSize: pageSize, inStock: inStockOnly ? true : null, lang: _app.lang);
      setState(() {
        items.addAll(next.items);
        total = next.total;
        _loadedPages = next.page;
      });
    } catch (_) {
      // 追加分页失败不打断已渲染列表。
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(sellerName.isNotEmpty ? sellerName : widget.sellerSlug)),
      body: _body(),
    );
  }

  Widget _body() {
    if (loading && items.isEmpty) return const SkeletonGrid();
    final e = error;
    if (e != null && items.isEmpty) {
      // 404 SELLER_NOT_FOUND 与详情面的 LISTING_NOT_FOUND 是两个不同的终态：
      // 这一面可能是 slug 打错，也可能是这家一条可见供给都没有了。
      if (e.isNotFound) {
        return TerminalStatePage(message: _l.raw('detail_offline_title'), homeLabel: _l.raw('back_home'), onHome: () => Navigator.pop(context));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_l.raw('detail_load_failed')),
            const SizedBox(height: 8),
            Text(_app.describeError(e) ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(_l.raw('retry'))),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - 24 - 8) / 2;
        return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Row(
              children: [
                Text(_l.fill('results_count', {'n': total}), style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                FilterChip(
                  label: Text(_l.raw('filter_in_stock')),
                  selected: inStockOnly,
                  onSelected: (v) {
                    setState(() => inStockOnly = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
        ),
        // 店铺页 items 是纯卡片：没有 is_promoted 可标——那一格不是平台卖出去的格子，
        // 标了就是虚假披露（§12.4）。
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: gridMainAxisExtent(columnWidth),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ProductCard(card: items[i], source: 'seller', view: 'seller|$widgetSlug|$inStockOnly', position: i, pageNumber: 1),
              childCount: items.length,
            ),
          ),
        ),
        if (loadingMore) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
        );
      },
    );
  }

  String get widgetSlug => widget.sellerSlug;
}
