import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/catalog_controller.dart';

/// 底部分类弹层：点一级类目就地展开子分类（手风琴，一次只开一个）。
/// 数字全部来自服务端出参（RPC 计数 + 父级滚上），App 不数行（§6.1）；
/// 只把 listing_count > 0 的类目做成出口——空类目出口是最坏的空状态。
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
  app.products.setCategory(result.slug); // null = 清掉类目收窄
  return true;
}

class _CategoryPick {
  const _CategoryPick(this.slug);
  final String? slug;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet();

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String? _expandedRootId;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final l = app.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(l.raw('tab_categories'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, const _CategoryPick(null)),
                  child: Text(l.raw('all_categories')),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.58,
              child: Consumer<CatalogController>(
                builder: (_, c, __) {
                  if (c.loading && c.catalog == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final withSupply = c.salvageRootsWithSupply;
                  final roots = withSupply.isEmpty ? c.rootCategories : withSupply;
                  if (roots.isEmpty) {
                    // 读失败或没有供给：说「没读到」，不假装「平台没有类目」。
                    return Center(
                      child: Text(c.failed ? l.raw('detail_load_failed') : l.raw('empty_hint'), style: Theme.of(context).textTheme.bodyMedium),
                    );
                  }
                  final currentCategory = app.products.category;
                  // 打开面板时展开当前类目所属的根（没有选中就都不展开）。
                  String? expanded = _expandedRootId;
                  if (expanded == null && currentCategory != null) {
                    final all = c.catalog?.categories ?? const <MarketCatalogNode>[];
                    final owner = all.where((n) => n.slug == currentCategory).toList();
                    if (owner.isNotEmpty) {
                      final root = roots.where((n) => n.id == owner.first.id || _isDescendant(c, owner.first.id, n.id)).toList();
                      if (root.isNotEmpty) expanded = root.first.id;
                    }
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final n in roots)
                        _RootRow(
                          node: n,
                          expanded: n.id == expanded,
                          currentCategory: currentCategory,
                          children: c.childrenOf(n.id).where((k) => k.listingCount > 0).toList(),
                          onToggle: () => setState(() => _expandedRootId = n.id == _expandedRootId ? null : n.id),
                          onPick: (slug) => Navigator.pop(context, _CategoryPick(slug)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDescendant(CatalogController c, String nodeId, String rootId) {
    var cursor = c.catalog?.categories.where((n) => n.id == nodeId).toList();
    int guard = 0;
    while (cursor != null && cursor.isNotEmpty && guard++ < 10) {
      final parent = cursor.first.parentId;
      if (parent == rootId) return true;
      cursor = c.catalog?.categories.where((n) => n.id == parent).toList();
    }
    return false;
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({
    required this.node,
    required this.expanded,
    required this.currentCategory,
    required this.children,
    required this.onToggle,
    required this.onPick,
  });

  final MarketCatalogNode node;
  final bool expanded;
  final String? currentCategory;
  final List<MarketCatalogNode> children;
  final VoidCallback onToggle;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final rootSelected = currentCategory == node.slug;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle, // 点击一级 = 展开/收起子分类
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: MarketTokens.line.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: rootSelected ? FontWeight.w800 : FontWeight.w600,
                      color: rootSelected ? MarketTokens.primary : MarketTokens.ink,
                    ),
                  ),
                ),
                Text('${node.listingCount}', style: const TextStyle(fontSize: 12, color: MarketTokens.muted)),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.keyboard_arrow_down, size: 22, color: MarketTokens.muted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 展开后第一枚永远是「全部 x」：整棵子树一起看的那一档。
                      _SubChip(label: '${node.name} · ${node.listingCount}', selected: rootSelected, onTap: () => onPick(node.slug)),
                      for (final k in children)
                        _SubChip(label: '${k.name} ${k.listingCount}', selected: currentCategory == k.slug, onTap: () => onPick(k.slug)),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SubChip extends StatelessWidget {
  const _SubChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE4DB) : MarketTokens.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? MarketTokens.primary : MarketTokens.line),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? MarketTokens.primary : MarketTokens.ink),
        ),
      ),
    );
  }
}
