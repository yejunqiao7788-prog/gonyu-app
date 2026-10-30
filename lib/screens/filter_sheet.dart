import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../state/products_controller.dart';

/// 移动筛选抽屉（§6.10）：价格 300 ms 静默提交，或 Enter，或卸载时——
/// 关掉抽屉本身就是一次卸载，丢掉这次冲刷等于丢掉买家刚设的条件。
Future<void> showFilterSheet(BuildContext context, ProductsController products) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(value: products, child: const _FilterSheet()),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

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
  }

  @override
  void dispose() {
    // 卸载冲刷：把还没落定的价格区间提交出去。
    _p.commitPendingPrice();
    _min.dispose();
    _max.dispose();
    _leadTime.dispose();
    super.dispose();
  }

  void _debouncePrice() => _p.setPrice(min: _min.text.isEmpty ? null : _min.text, max: _max.text.isEmpty ? null : _max.text);

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.raw('filter_title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _min, keyboardType: TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _debouncePrice(), onSubmitted: (_) => _p.setPrice(min: _min.text.isEmpty ? null : _min.text, max: _max.text.isEmpty ? null : _max.text, immediate: true), decoration: InputDecoration(labelText: l.raw('filter_price_min'), prefixText: '\u00A0'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _max, keyboardType: TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _debouncePrice(), onSubmitted: (_) => _p.setPrice(min: _min.text.isEmpty ? null : _min.text, max: _max.text.isEmpty ? null : _max.text, immediate: true), decoration: InputDecoration(labelText: l.raw('filter_price_max'), prefixText: '\u00A0'))),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.raw('filter_price'), style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
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
            const SizedBox(height: 16),
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
      ),
    );
  }
}
