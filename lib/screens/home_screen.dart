import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/catalog_controller.dart';
import '../state/products_controller.dart';
import '../widgets/common.dart';
import '../widgets/product_card.dart';
import 'filter_sheet.dart';

/// 首页（微信小店式，业主 2026-10-31 决定）：顶部只有搜索一行；
/// 类目走底部「分类」中枢，排序/日历/价格收进漏斗面板；
/// 收窄条件生效后将显示一条可清除的 chip 行——chip 行只在有内容时占高度。
/// 商品双列大图从屏幕第二屏位置开始铺满。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialSeller});
  final String? initialSeller;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final AppState _app;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  final ScrollController _scroll = ScrollController();

  ProductsController get _products => _app.products;
  CatalogController get _catalog => _app.catalog;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    if (widget.initialSeller != null) _products.seller = widget.initialSeller;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _products.loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () => _products.setSearch(value));
  }

  MarketL10n get _l => _app.l10n;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _products),
        ChangeNotifierProvider.value(value: _catalog),
      ],
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(),
              Consumer<ProductsController>(
                builder: (_, p, __) {
                  final hasChips = p.category != null || p.listedDay != null || p.seller != null || (p.q != null);
                  if (!hasChips) return const SizedBox.shrink();
                  return _activeChips(p);
                },
              ),
              Consumer<ProductsController>(
                builder: (_, p, __) => p.servingStale ? StaleBanner(label: _l.raw('stale_banner')) : const SizedBox.shrink(),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(color: MarketTokens.surface, borderRadius: BorderRadius.circular(21), border: Border.all(color: MarketTokens.line)),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search, size: 19, color: MarketTokens.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (v) {
                        _searchDebounce?.cancel();
                        _products.setSearch(v);
                      },
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _l.raw('search_placeholder'),
                        hintStyle: const TextStyle(fontSize: 14, color: MarketTokens.muted),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        suffixIcon: Consumer<ProductsController>(
                          builder: (_, p, __) => (p.q == null && _search.text.isEmpty)
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _search.clear();
                                    _products.setSearch('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Consumer<ProductsController>(
            builder: (_, p, __) => IconButton(
              icon: Icon(Icons.tune, color: _filtersActive(p) ? MarketTokens.primary : MarketTokens.ink),
              onPressed: () async {
                // 关掉移动筛选抽屉本身就是一次卸载：卸载时冲刷待提交的价格（§6.10）。
                await showFilterSheet(context, _products);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _filtersActive(ProductsController p) => p.inStock || p.onlinePay || p.leadTimeMax != null || p.minPrice != null || p.maxPrice != null || p.sort != 'recommended';

  Widget _activeChips(ProductsController p) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          if (p.category != null) _chip(p.categoryName(_catalog), () => p.setCategory(null)),
          if (p.listedDay != null) _chip(p.listedDay!, () => p.setListedDay(null)),
          if (p.seller != null) _chip(p.seller!, () { p.seller = null; p.trackFilterChange(); p.refresh(); p.loadFacet(); }),
          if (p.q != null) _chip('“${p.q}”', () { _search.clear(); p.setSearch(''); }),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onClear) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        label: Text(label, style: const TextStyle(fontSize: 12.5, color: MarketTokens.ink)),
        backgroundColor: const Color(0xFFFFE4DB),
        deleteIcon: const Icon(Icons.close, size: 14),
        onPressed: onClear,
        onDeleted: onClear,
      ),
    );
  }

  Widget _body() {
    return Consumer2<ProductsController, CatalogController>(
      builder: (context, p, c, _) {
        if (p.loading && p.items.isEmpty) return const SkeletonGrid(crossAxisCount: 2, itemHeight: 300);
        if (p.error != null && p.items.isEmpty) return _loadFailed(p);

        final source = p.seller != null ? 'seller' : (p.q != null ? 'search' : (p.category != null ? 'category' : 'home'));
        final view = '${p.q ?? ''}|${p.category ?? ''}|${p.sort}|${p.listedDay ?? ''}';

        return LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth = (constraints.maxWidth - 24 - 8) / 2;
            final extent = gridMainAxisExtent(columnWidth);
            final delegate = SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: extent,
            );
            return RefreshIndicator(
              onRefresh: () async {
                await p.refresh();
                await p.loadFacet();
              },
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  if (p.items.isEmpty && p.narrowed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 8),
                        child: Column(
                          children: [
                            Text(_l.raw('empty_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(_l.raw('empty_hint'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            // 补救类目条只给有供给的根类目——把空类目做成出口是最坏的空状态。
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [for (final n in c.salvageRootsWithSupply.take(6)) ActionChip(label: Text('${n.name} (${n.listingCount})'), onPressed: () => p.setCategory(n.slug))],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
                        child: Text(_l.fill('results_count', {'n': p.total}), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MarketTokens.muted)),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    sliver: SliverGrid(
                      gridDelegate: delegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => ProductCard(card: p.items[i], source: source, view: view, position: i, pageNumber: p.page),
                        childCount: p.items.length,
                      ),
                    ),
                  ),
                  if (p.salvageItems.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                        child: Text(_l.raw('salvage_title'), style: Theme.of(context).textTheme.titleSmall),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      sliver: SliverGrid(
                        gridDelegate: delegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => ProductCard(card: p.salvageItems[i], source: p.category != null ? 'category' : 'home', view: 'salvage|${p.category ?? ''}', position: i, pageNumber: 1),
                          childCount: p.salvageItems.length,
                        ),
                      ),
                    ),
                  ],
                  if (p.loadingMore) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _loadFailed(ProductsController p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_l.raw('detail_load_failed'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_app.describeError(p.error!) ?? '', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => p.refresh(), child: Text(_l.raw('retry'))),
          ],
        ),
      ),
    );
  }
}
