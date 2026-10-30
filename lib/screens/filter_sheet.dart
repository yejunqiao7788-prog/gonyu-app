import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/products_controller.dart';
import '../widgets/listed_calendar.dart';

/// 移动筛选抽屉：现在承担「从首页收起来的一切」——排序、上新日历、价格、库存、支付、交付。
/// 价格仍是 300 ms 静默提交（或 Enter、或卸载时）：关掉抽屉本身就是一次卸载，
/// 丢掉这次冲刷等于丢掉买家刚设的条件（§6.10）。
Future<void> showFilterSheet(BuildContext context, ProductsController products) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => ChangeNotifierProvider.value(
        value: products,
        child: _FilterSheet(scrollController: scrollController),
      ),
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _leadTime;
  late final AppState _app;
  late ProductsController _p;
  late bool _inStock;
  late bool _onlinePay;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _p = context.read<ProductsController>();
    _min = TextEditingController(text: _p.minPriceRaw ?? '');
    _max = TextEditingController(text: _p.maxPriceRaw ?? '');
    _leadTime = TextEditingController(text: _p.leadTimeMax?.toString() ?? '');
    _inStock = _p.inStock;
    _onlinePay = _p.onlinePay;
    // 日历分面若还没到（首屏从未加载过），打开面板时补一次。
    if (_p.facet == null && _p.facetError == null) _p.loadFacet();
  }

  @override
  void dispose() {
    _p.commitPendingPrice();
    _min.dispose();
    _max.dispose();
    _leadTime.dispose();
    super.dispose();
  }

  void _debouncePrice() => _p.setPrice(min: _min.text.isEmpty ? null : _min.text, max: _max.text.isEmpty ? null : _max.text);

  void _commitPriceNow() => _p.setPrice(min: _min.text.isEmpty ? null : _min.text, max: _max.text.isEmpty ? null : _max.text, immediate: true);

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Text(l.raw('filter_title'), style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              children: [
                // ---- 排序：「推荐」和其它四档一样是一档，换档会真的改变条数（§6.2）----
                Text(l.raw('sort'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < ProductsController.sortOptions.length; i++)
                      ChoiceChip(
                        label: Text(l.raw(ProductsController.sortKeyFor(i))),
                        selected: ProductsController.sortOptions[i] == _p.sort,
                        onSelected: (_) => setState(() => _p.setSort(ProductsController.sortOptions[i])),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // ---- 上新日历（数据与判据不动，只是从首页收进来，§6.3）----
                ListedCalendarStrip(embedded: true),
                const SizedBox(height: 12),
                // ---- 价格 ----
                Text(l.raw('filter_price'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _min, keyboardType: TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _debouncePrice(), onSubmitted: (_) => _commitPriceNow(), decoration: InputDecoration(labelText: l.raw('filter_price_min')))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _max, keyboardType: TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _debouncePrice(), onSubmitted: (_) => _commitPriceNow(), decoration: InputDecoration(labelText: l.raw('filter_price_max')))),
                  ],
                ),
                const SizedBox(height: 12),
                // ---- 开关 ----
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.raw('filter_in_stock')),
                  value: _inStock,
                  onChanged: (v) {
                    setState(() => _inStock = v);
                    _p.applyFilters(inStock: v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.raw('filter_online_pay')),
                  value: _onlinePay,
                  onChanged: (v) {
                    setState(() => _onlinePay = v);
                    _p.applyFilters(onlinePay: v);
                  },
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _leadTime,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _p.applyFilters(leadTimeMax: int.tryParse(_leadTime.text)),
                  decoration: InputDecoration(labelText: l.raw('filter_lead_time')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  _min.clear();
                  _max.clear();
                  _leadTime.clear();
                  setState(() {
                    _inStock = false;
                    _onlinePay = false;
                  });
                  _p.setPrice(min: null, max: null, immediate: true);
                  _p.applyFilters(inStock: false, onlinePay: false, clearLeadTime: true);
                },
                child: Text(l.raw('reset')),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.raw('apply'))),
            ],
          ),
        ],
      ),
    );
  }
}
