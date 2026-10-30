import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 骨架屏：冷启动那一两秒用骨架呈现，不转成失败重试（§3.3）。
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.rows = 4, this.crossAxisCount = 1, this.itemHeight = 118});

  final int rows;
  final int crossAxisCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: itemHeight,
      ),
      itemCount: rows * crossAxisCount,
      itemBuilder: (_, __) => const _SkeletonBox(),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox();

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_pulse),
      child: Container(
        decoration: BoxDecoration(color: MarketTokens.surfaceDim, borderRadius: BorderRadius.circular(MarketTokens.radius)),
      ),
    );
  }
}

/// 终点态整页（404 类）：一句事实 + 回首页，不给重试按钮。
class TerminalStatePage extends StatelessWidget {
  const TerminalStatePage({super.key, required this.message, required this.homeLabel, this.onHome});

  final String message;
  final String homeLabel;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 18),
            FilledButton(onPressed: onHome ?? () => Navigator.of(context).pop(), child: Text(homeLabel)),
          ],
        ),
      ),
    );
  }
}

/// stale 横幅：列表/店铺页/日历允许展示上一次读数，但必须带横幅（§8.7）。
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// 底部悬浮层偏移必须由被测元素自己发布的高度推导，不用像素常量（§8.8）。
/// 吸底条把自己高度写进这里，客服面板/回到顶部都读它。
class DockHeight extends InheritedWidget {
  const DockHeight({super.key, required this.height, required super.child});
  final double height;
  static double of(BuildContext context) => context.findAncestorWidgetOfExactType<DockHeight>()?.height ?? 0;
  @override
  bool updateShouldNotify(DockHeight oldWidget) => oldWidget.height != height;
}

/// 「未取到」与 0 是两个结论：短横 + 语义由调用方文案给出（§7.8）。
class NullDash extends StatelessWidget {
  const NullDash({super.key, this.tooltip});
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dash = Text('—', style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted));
    if (tooltip == null) return dash;
    return Tooltip(message: tooltip!, child: dash);
  }
}

class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.items, required this.selectedIndex, this.onSelected});
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            ChoiceChip(
              label: Text(items[i]),
              selected: i == selectedIndex,
              onSelected: (_) => onSelected?.call(i),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
