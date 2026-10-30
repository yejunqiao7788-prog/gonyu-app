import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/catalog_controller.dart';

/// 底部分类弹层（微信小店式）：点中间按钮升起一层类目面板，
/// 选完即走——首页顶部不再为类目常驻一行。数字仍全部来自服务端出参（§6.1）。
Future<bool> showCategorySheet(BuildContext context) async {
  final app = context.read<AppState>();
  final result = await showModalBottomSheet<_CategoryPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MarketTokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => ChangeNotifierProvider<CatalogController>.value(
      value: app.catalog,
      child: const _CategorySheet(),
    ),
  );
  if (result == null) return false;
  if (result.slug == null) {
    app.products.setCategory(null);
  } else {
    app.products.setCategory(result.slug);
  }
  return true;
}

class _CategoryPick {
  const _CategoryPick(this.slug);
  final String? slug;
}

class _CategorySheet extends StatelessWidget {
  const _CategorySheet();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final l = app.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(l.raw('tab_categories'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, const _CategoryPick(null)),
                  child: Text(l.raw('all_categories')),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Consumer<CatalogController>(
              builder: (_, c, __) {
                if (c.loading && c.catalog == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final roots = c.salvageRootsWithSupply;
                if (roots.isEmpty) {
                  // 读失败或没有供给：说「没读到」，不假装「平台没有类目」。
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(c.failed ? l.raw('detail_load_failed') : l.raw('empty_hint'), style: Theme.of(context).textTheme.bodyMedium),
                  );
                }
                final currentCategory = app.products.category;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: roots.length > 9 ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                        children: [
                          for (int i = 0; i < roots.length; i++)
                            _CategoryTile(
                              node: roots[i],
                              selected: roots[i].slug == currentCategory,
                              color: _palette[i % _palette.length],
                              onTap: () => Navigator.pop(context, _CategoryPick(roots[i].slug)),
                            ),
                        ],
                      ),
                    ),
                    // 选中/首个根类目的下一级快捷入口：类目是视图不是页面，所以只在本层展开。
                    _SubRow(nodes: _subOf(context, roots, currentCategory)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<MarketCatalogNode> _subOf(BuildContext context, List<MarketCatalogNode> roots, String? currentCategory) {
    final c = context.read<CatalogController>();
    final matches = roots.where((n) => n.slug == currentCategory).toList();
    final target = matches.isEmpty ? roots.first : matches.first;
    return c.childrenOf(target.id).where((n) => n.listingCount > 0).take(8).toList();
  }
}

class _SubRow extends StatelessWidget {
  const _SubRow({required this.nodes});
  final List<MarketCatalogNode> nodes;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final app = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final n in nodes)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${n.name} ${n.listingCount}', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: app.products.category == n.slug,
                  onSelected: (_) => Navigator.pop(context, _CategoryPick(n.slug)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.node, required this.color, required this.selected, required this.onTap});
  final MarketCatalogNode node;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? const Color(0xFFFFE4DB) : MarketTokens.background,
          border: Border.all(color: selected ? MarketTokens.primary : MarketTokens.line.withValues(alpha: 0.6)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Center(
                child: Text(
                  (node.name.isEmpty ? '·' : node.name[0]).toUpperCase(),
                  style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? MarketTokens.primary : MarketTokens.ink)),
            Text('${node.listingCount}', style: const TextStyle(fontSize: 11, color: MarketTokens.muted)),
          ],
        ),
      ),
    );
  }
}

const List<Color> _palette = [
  Color(0xFFFF5A3C),
  Color(0xFF2E7DD1),
  Color(0xFF1B7F4B),
  Color(0xFFB4690E),
  Color(0xFF8E44AD),
  Color(0xFFC2185B),
  Color(0xFF00897B),
  Color(0xFF5C6BC0),
];
