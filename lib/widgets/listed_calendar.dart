import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/products_controller.dart';

/// 上架日历（§6.3）：窗口固定 30 天、永不跟着选中日缩短；「今天」是服务端回显的那一个；
/// truncated 为真时格子数字是下界，要能说「至少 N」；读不到窗口就整块不渲染——
/// 宁可不画日历，也不能退化成全表扫。
class ListedCalendarStrip extends StatelessWidget {
  const ListedCalendarStrip({super.key, this.embedded = false});

  /// embedded=true 时用于筛选面板内：不占首页行高，字号一致。
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final l = app.l10n;
    return Consumer<ProductsController>(
      builder: (_, p, __) {
        final facet = p.facet;
        if (facet == null || !facet.renderable) return const SizedBox.shrink();
        final byDate = {for (final row in facet.listedDays) row.date: row.count};
        final days = _windowDates(facet.window!.from, facet.window!.days);
        if (days.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Text(l.raw('calendar_title'), style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  if (p.listedDay != null)
                    ActionChip(
                      label: Text(l.raw('reset')),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => p.setListedDay(null),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 66,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final day = days[i];
                  final count = byDate[day];
                  final selected = p.listedDay == day;
                  final isToday = facet.today == day;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: count == null
                        ? null // 空日不可选：点了也是 0 条，别给假出口
                        : () => p.setListedDay(selected ? null : day),
                    child: Container(
                      width: 52,
                      decoration: BoxDecoration(
                        color: selected ? MarketTokens.primary : MarketTokens.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isToday ? MarketTokens.primary : MarketTokens.line),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(day.substring(8), style: TextStyle(color: selected ? Colors.white : MarketTokens.ink, fontWeight: FontWeight.w700)),
                          Text(
                            count == null ? '·' : (facet.truncated ? '≥$count' : '$count'), // 下界语义要说出口（§7.8）
                            style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : MarketTokens.muted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 从 window.from（yyyy-MM-dd）数 days 天。只数日历日期，不做毫秒加法——
  /// 夏令时切换那天是 23 或 25 小时，半开区间仍要对（§5.3）。
  static List<String> _windowDates(String from, int days) {
    final start = DateTime.tryParse(from);
    if (start == null) return const [];
    final out = <String>[];
    for (int i = 0; i < days; i++) {
      final d = DateTime.utc(start.year, start.month, start.day).add(Duration(days: i));
      out.add('${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
    return out;
  }
}
