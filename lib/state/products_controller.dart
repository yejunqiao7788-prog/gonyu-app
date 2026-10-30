import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/market_api.dart';
import '../data/models.dart';
import 'app_state.dart';
import 'catalog_controller.dart';

/// 首页/列表的查询状态机。三条不能写错的（§5.2、§6.1、§6.10）：
/// - 采纳服务端回显的 page / sort（越界回落第 1 页，不采纳就是「第 8 页显示第 1 页内容」）。
/// - 每一轮新筛选都要骨架屏，把上一轮结果留在新条件下是对「哪条结果属于哪个查询」说谎。
/// - 空结果补救只在「结果为空且确实被收窄」时发请求；降权补救不需要特殊 UI。
class ProductsController extends ChangeNotifier {
  ProductsController(this._app) {
    refresh(reset: true);
    loadFacet();
  }

  final AppState _app;
  MarketApi get _api => _app.marketApi;

  // ---------- 筛选状态 ----------
  String? q;
  String? category; // slug
  String? seller; // slug，不是店名
  String sort = 'recommended'; // 六档之一：推荐是唯一会藏 muted 的档
  String? minPriceRaw;
  String? maxPriceRaw;
  bool inStock = false;
  bool onlinePay = false;
  int? leadTimeMax;
  String? listedDay; // yyyy-MM-dd（Europe/Kyiv 的日子由服务端裁定）

  static const List<String> sortOptions = ['recommended', 'newest', 'price_asc', 'price_desc', 'stock'];

  static String sortKeyFor(int i) => const ['sort_recommended', 'sort_newest', 'sort_price_asc', 'sort_price_desc', 'sort_stock'][i];

  double? get minPrice => double.tryParse(minPriceRaw ?? '');
  double? get maxPrice => double.tryParse(maxPriceRaw ?? '');

  bool get narrowed => q != null && q!.isNotEmpty || minPrice != null || maxPrice != null || inStock || onlinePay;

  Timer? _priceDebounce;

  /// 价格输入 300 ms 静默提交（或 Enter、或卸载时）：逐字符提交会让「1200」变成四次公开查询。
  void setPrice({String? min, String? max, bool immediate = false}) {
    minPriceRaw = min;
    maxPriceRaw = max;
    _priceDebounce?.cancel();
    if (immediate) {
      refresh(reset: true);
      loadFacet();
    } else {
      _priceDebounce = Timer(const Duration(milliseconds: 300), () {
        refresh(reset: true);
        loadFacet();
      });
    }
  }

  void commitPendingPrice() {
    if (_priceDebounce?.isActive ?? false) {
      _priceDebounce!.cancel();
      refresh(reset: true);
      loadFacet();
    }
  }

  void setSort(String value) {
    sort = value;
    trackFilterChange();
    refresh(reset: true);
    loadFacet();
  }

  void setCategory(String? slug) {
    // 选类目 chip 时丢掉所有收窄条件但保留 sort（阅读顺序不是收窄条件）。
    category = slug;
    q = null;
    minPriceRaw = null;
    maxPriceRaw = null;
    inStock = false;
    onlinePay = false;
    leadTimeMax = null;
    listedDay = null;
    trackFilterChange();
    refresh(reset: true);
    loadFacet();
  }

  void setSearch(String value) {
    q = value.trim().isEmpty ? null : value.trim();
    _app.analytics.track(MarketEventRow(type: 'search', query: q, source: 'search', sort: sort));
    trackFilterChange();
    refresh(reset: true);
    loadFacet();
  }

  void setListedDay(String? day) {
    listedDay = day;
    trackFilterChange();
    refresh(reset: true);
    loadFacet();
  }

  void applyFilters({String? seller, bool? inStock, bool? onlinePay, int? leadTimeMax, bool clearLeadTime = false}) {
    if (seller != null) this.seller = seller;
    if (inStock != null) this.inStock = inStock;
    if (onlinePay != null) this.onlinePay = onlinePay;
    if (clearLeadTime) {
      this.leadTimeMax = null;
    } else if (leadTimeMax != null) {
      this.leadTimeMax = leadTimeMax;
    }
    trackFilterChange();
    refresh(reset: true);
    loadFacet();
  }

  void trackFilterChange() {
    _app.analytics.track(MarketEventRow(
      type: 'filter_change',
      categorySlug: category,
      sellerSlug: seller,
      sort: sort,
      query: q,
      source: seller != null ? 'seller' : (q != null ? 'search' : (category != null ? 'category' : 'home')),
    ));
  }

  /// chip 回显用类目名（名字来自服务端折好的那份 catalog，不自己拼）。
  String categoryName(CatalogController catalog) {
    final slug = category;
    if (slug == null) return '';
    final all = catalog.catalog?.categories ?? const [];
    final match = all.where((n) => n.slug == slug).toList();
    return match.isEmpty ? slug : match.first.name;
  }

  MarketQuery _buildQuery({int? page}) => MarketQuery(
        q: q,
        category: category,
        sort: sort,
        minPrice: minPrice,
        maxPrice: maxPrice,
        onlinePay: onlinePay ? true : null,
        inStock: inStock ? true : null,
        leadTimeMax: leadTimeMax,
        seller: seller,
        listedDay: listedDay,
        page: page,
        pageSize: 24,
        lang: _app.lang,
      );

  // ---------- 读数状态 ----------

  List<MarketCard> items = const [];
  int page = 1;
  int totalPages = 1;
  int total = 0;
  bool loading = true;
  bool loadingMore = false;
  bool loadingSalvage = false;
  List<MarketCard> salvageItems = const [];
  MarketApiException? error;
  MarketApiException? facetError;
  MarketListedDayFacet? facet;
  DateTime? fetchedAt; // stale 横幅的时间戳
  bool servingStale = false;

  Future<void> refresh({bool reset = true}) async {
    if (reset) {
      loading = true;
      error = null;
      salvageItems = const [];
    }
    notifyListeners();
    try {
      final result = await _api.listProducts(_buildQuery(page: 1));
      page = result.page; // 采纳服务端回显
      items = result.items;
      total = result.total;
      totalPages = result.totalPages;
      sort = result.sort; // 生效档位回显：未知值服务端回落 recommended
      error = null;
      servingStale = false;
      fetchedAt = DateTime.now();
      if (total == 0 && narrowed) _loadSalvage();
    } on MarketApiException catch (e) {
      error = e;
      servingStale = items.isNotEmpty; // 失败时保留上一次列表 + 横幅，不显示「没有结果」
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loadingMore || loading || page >= totalPages || items.isEmpty) return;
    loadingMore = true;
    notifyListeners();
    try {
      final result = await _api.listProducts(_buildQuery(page: page + 1));
      page = result.page;
      items = [...items, ...result.items];
      total = result.total;
      totalPages = result.totalPages;
    } on MarketApiException {
      // 加载更多失败不打断已渲染列表。
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  /// 筛空补救：结果 0 条且确实做了收窄时，去条件重读一次类目/推荐流。
  /// 曝光走自己的去重 view 键，但持久判别字段没有——source 仍按落点记。
  Future<void> _loadSalvage() async {
    loadingSalvage = true;
    notifyListeners();
    try {
      final salvaged = await _api.listProducts(MarketQuery(
        category: category,
        sort: 'recommended',
        page: 1,
        pageSize: 24,
        lang: _app.lang,
      ));
      salvageItems = salvaged.items;
    } catch (_) {
      salvageItems = const []; // 补救读失败时只藏起这一块，不碰主错误态
    } finally {
      loadingSalvage = false;
      notifyListeners();
    }
  }

  Future<void> loadFacet() async {
    try {
      facet = await _api.getListedDays(_buildQuery());
      facetError = null;
    } on MarketApiException catch (e) {
      facetError = e;
      facet = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _priceDebounce?.cancel();
    super.dispose();
  }
}
