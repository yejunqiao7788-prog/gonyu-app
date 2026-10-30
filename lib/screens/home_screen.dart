import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../state/app_state.dart';
import '../state/products_controller.dart';
import '../widgets/common.dart';
import '../widgets/listed_calendar.dart';
import '../widgets/product_card.dart';
import 'filter_sheet.dart';

/// 公域首页：类目入口、日历、筛选 chips 共用同一份 catalog 状态（状态提升到这里，
/// 避免「导航显示当前类目」和「列表按类目筛选」两份真值，§6.1）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialSeller});
  final String? initialSeller;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final AppState _app;
  late final ProductsController _products;
  late final CatalogController _catalog;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _products = ProductsController(_app);
    if (widget.initialSeller != null) _products.seller = widget.initialSeller;
    _catalog = CatalogController(_app);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _products.dispose();
    _catalog.dispose();
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
          child: Column(
            children: [
              _topBar(),
              _categoryChips(),
              _sortChips(),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (v) {
                _searchDebounce?.cancel();
                _products.setSearch(v);
              },
              decoration: InputDecoration(
                hintText: _l.raw('search_placeholder'),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () async {
                    // 关掉移动筛选抽屉本身就是一次卸载：卸载时冲刷待提交的价格（§6.10）。
                    await showFilterSheet(context, _products);
                  },
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.language), tooltip: _l.langCode.toUpperCase(), onPressed: _pickLanguage),
        ],
      ),
    );
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lang in _l.langs)
              ListTile(
                title: Text('${lang == _app.lang ? '✓  ' : '    '}${_l.raw('lang_$lang')}'),
                onTap: () => Navigator.pop(ctx, lang),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _app.lang) {
      // 语言切换后所有请求的 lang 参数与界面一致；类目 name 是服务端折好的，必须重取。
      await _app.setLang(picked);
      _catalog.reloadForLang();
      _products.refresh();
      _products.loadFacet();
    }
  }

  Widget _categoryChips() {
    return Consumer2<CatalogController, ProductsController>(
      builder: (_, c, p, __) {
        if (c.loading && c.catalog == null) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator(minHeight: 2));
        }
        final roots = c.rootCategories;
        if (roots.isEmpty) return const SizedBox.shrink();
        // chip 上的数字直接打印出参（RPC 计数 + 父级滚动汇总），绝不用「本页返回了几条」代替。
        final labels = [_l.raw('all_categories'), for (final n in roots) '${n.name} (${n.listingCount})'];
        var selected = 0;
        if (p.category != null) {
          final i = roots.indexWhere((n) => n.slug == p.category);
          if (i >= 0) selected = i + 1;
        }
        return ChipRow(items: labels, selectedIndex: selected, onSelected: (i) => p.setCategory(i == 0 ? null : roots[i - 1].slug));
      },
    );
  }

  Widget _sortChips() {
    return Consumer<ProductsController>(
      builder: (_, p, __) => ChipRow(
        items: const ['sort_recommended', 'sort_newest', 'sort_price_asc', 'sort_price_desc', 'sort_stock'].map(_l.raw).toList(),
        // 「推荐」和其它四档一样是一档，而且换档会真的改变条数（§6.2）。
        selectedIndex: ProductsController.sortOptions.indexOf(p.sort),
        onSelected: (i) => p.setSort(ProductsController.sortOptions[i]),
      ),
    );
  }

  Widget _body() {
    return Consumer2<ProductsController, CatalogController>(
      builder: (context, p, c, _) {
        if (p.loading && p.items.isEmpty) return const SkeletonGrid();
        if (p.error != null && p.items.isEmpty) return _loadFailed(p);

        final source = p.seller != null ? 'seller' : (p.q != null ? 'search' : (p.category != null ? 'category' : 'home'));
        final view = '${p.q ?? ''}|${p.category ?? ''}|${p.sort}|${p.listedDay ?? ''}';

        return RefreshIndicator(
          onRefresh: () async {
            await p.refresh();
            await p.loadFacet();
          },
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              const SliverToBoxAdapter(child: ListedCalendarStrip()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  child: Text(_l.fill('results_count', {'n': p.total}), style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              if (p.items.isEmpty && p.narrowed) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 28, 14, 8),
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
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ProductCard(card: p.items[i], source: source, view: view, position: i, pageNumber: p.page),
                    ),
                    childCount: p.items.length,
                  ),
                ),
              ),
              if (p.salvageItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Text(_l.raw('salvage_title'), style: Theme.of(context).textTheme.titleSmall),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        // 补救网格用自己的 view 键、page 恒为 1、sort 恒为 recommended（§6.10）。
                        child: ProductCard(card: p.salvageItems[i], source: p.category != null ? 'category' : 'home', view: 'salvage|${p.category ?? ''}', position: i, pageNumber: 1),
                      ),
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
