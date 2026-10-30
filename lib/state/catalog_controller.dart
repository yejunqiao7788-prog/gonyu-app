import 'package:flutter/foundation.dart';

import '../data/models.dart';
import 'app_state.dart';

/// 类目树：整个公域首页只取一次（导航、页脚、筛选共用一份真值，§6.1）。
/// 现在它住在 AppState 上——首页 pill 行、底部分类弹层、空结果补救条读的都是这一份。
class CatalogController extends ChangeNotifier {
  CatalogController(this._app) {
    load();
  }

  final AppState _app;
  MarketCatalog? catalog;
  bool loading = true;
  bool failed = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      catalog = await _app.marketApi.getCatalog(_app.lang);
      failed = false;
    } catch (_) {
      failed = true; // 读失败 ≠ 「平台没有类目」
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 语言变了必须重取：name 是服务端按 lang 折好的单字段。
  Future<void> reloadForLang() async {
    catalog = null;
    await load();
  }

  List<MarketCatalogNode> get rootCategories {
    final c = catalog;
    if (c == null) return const [];
    final roots = c.categories.where((n) => n.parentId == null).toList();
    roots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return roots;
  }

  List<MarketCatalogNode> childrenOf(String parentId) {
    final c = catalog;
    if (c == null) return const [];
    final kids = c.categories.where((n) => n.parentId == parentId).toList();
    kids.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return kids;
  }

  /// 补救类目条只给 listing_count > 0 的根类目——把空类目做成出口是最坏的空状态。
  List<MarketCatalogNode> get salvageRootsWithSupply => rootCategories.where((n) => n.listingCount > 0).toList();
}
