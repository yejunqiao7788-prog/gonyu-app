import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../data/analytics_binding.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// 留资表单（§6.6、§8.7）。形状只有一种正确的：
/// - 提交按钮永远可点；状态判定来自响应错误码，不来自本地对价格/库存字段的推断。
/// - 已登录买家默认「用我保存的号码」：请求体只带 use_saved_contact: true，不带任何号码字节；
///   掩码号（+380****88）过不了 normalizePhone，它不是一个可以预填的值。
/// - 客户端不发送金额：请求体里没有 unit_price / subtotal 的位置（§7.3）。
/// - 会话失效的登录买家提交时拿到 401 系列的「请重新登录」，且不清空已填字段（§4.5）。
Future<void> showLeadForm(BuildContext context, MarketProductDetail detail) async {
  final app = context.read<AppState>();
  app.analytics.track(AnalyticsBinding.leadFormOpen(detail.card.slug));
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(value: app, child: _LeadForm(detail: detail)),
  );
}

class _LeadForm extends StatefulWidget {
  const _LeadForm({required this.detail});
  final MarketProductDetail detail;

  @override
  State<_LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends State<_LeadForm> {
  late final AppState _app;
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _box = TextEditingController();
  final _piece = TextEditingController();
  final _note = TextEditingController();
  bool _useSaved = false;
  bool _consent = false; // 营销同意默认关闭是库里的形状（§9.4），不能因本地存过 true 就替买家勾上
  bool _showPhoneField = false;
  bool _submitting = false;
  String? _formError;
  String? _retryHint;
  MarketLeadResult? _result;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _useSaved = _app.signedIn;
    if (_app.signedIn) _name.text = _app.me?.name ?? '';
  }

  @override
  void dispose() {
    for (final c in [_phone, _name, _email, _qty, _box, _piece, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _formError = null;
      _retryHint = null;
    });
    final useSaved = _useSaved && !_showPhoneField; // 「改用其他号码」时退回手填号码
    try {
      final result = await _app.marketApi.submitLead(
        slug: widget.detail.card.slug,
        phone: useSaved ? null : _phone.text,
        useSavedContact: useSaved ? true : null,
        name: _name.text.isEmpty ? null : _name.text,
        email: _email.text.isEmpty ? null : _email.text,
        // quantity 照实提交；起订量判定是服务端裁决（BELOW_MIN_ORDER + details.min_order_qty），App 不裁。
        quantity: int.tryParse(_qty.text),
        boxCount: int.tryParse(_box.text),
        pieceCount: int.tryParse(_piece.text),
        demandNote: _note.text.isEmpty ? null : _note.text,
        consentMarketing: _consent,
        lang: _app.lang,
        sessionId: _app.analytics.sessionId,
      );
      _app.analytics.track(AnalyticsBinding.leadFormSubmit(widget.detail.card.slug));
      if (mounted) setState(() => _result = result);
    } on MarketApiException catch (e) {
      if (!mounted) return;
      final code = e.code;
      setState(() {
        if (code == 'BELOW_MIN_ORDER' || code == 'OVER_STOCK') {
          _formError = _app.l10n.errorText(e); // 留在当前屏，标红数量字段
          _retryHint = _app.l10n.raw('lead_note_retry_hint');
        } else if (code == 'OUT_OF_STOCK') {
          _formError = _app.l10n.errorText(e); // 提交瞬间库存被吃掉：改数量可重试
          _retryHint = _app.l10n.raw('lead_note_retry_hint');
        } else if (code == 'LISTING_UNAVAILABLE' || code == 'TENANT_UNAVAILABLE') {
          _formError = _app.l10n.errorText(e); // 「已下架/暂不可接单」，不是笼统「提交失败」
        } else if (code == 'BUYER_LOGIN_REQUIRED' || code == 'BUYER_SESSION_INVALID' || code == 'BUYER_SESSION_EXPIRED') {
          // 不要把一次登录问题说成买家的输入错误，也不清空买家打过的字段。
          _formError = _app.l10n.raw('err_relogin');
        } else {
          _formError = _app.l10n.errorText(e); // D4：process_order_v2 的库存不足句原样上屏
          if (e.retryable) _retryHint = _app.l10n.raw('lead_note_retry_hint');
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    if (_result != null) return _SuccessView(result: _result!, title: widget.detail.card.title);
    final detail = widget.detail;
    return Padding(
      // 键盘不能盖住留资表单（§8.8）：表单滚到键盘上方。
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.raw('lead_title'), style: Theme.of(context).textTheme.titleMedium)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            if (_app.signedIn) _savedContactBlock(l),
            if (!_app.signedIn || !_useSaved || _showPhoneField)
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.raw('lead_phone')),
              ),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: InputDecoration(labelText: l.raw('lead_name'))),
            const SizedBox(height: 10),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.raw('lead_email'))),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.raw('lead_quantity')),
                  ),
                ),
                const SizedBox(width: 10),
                if (detail.card.minOrderQty != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: MarketTokens.surfaceDim, borderRadius: BorderRadius.circular(8)),
                    child: Text(l.fill('min_order', {'n': detail.card.minOrderQty})),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: _box, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.raw('lead_box_count')))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _piece, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.raw('lead_piece_count')))),
              ],
            ),
            const SizedBox(height: 10),
            TextField(controller: _note, minLines: 2, maxLines: 4, maxLength: 500, decoration: InputDecoration(labelText: l.raw('lead_note'))),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: Text(l.raw('lead_consent'), style: Theme.of(context).textTheme.bodySmall),
            ),
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_formError!, style: const TextStyle(color: Color(0xFFB3261E))),
              ),
            if (_retryHint != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_retryHint!, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // 按钮永远可点（只要页面是渲染出来的），可点状态不由缓存值支撑。
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? l.raw('lead_submitting') : l.raw('cta_submit_lead')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedContactBlock(dynamic l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone, size: 16, color: MarketTokens.muted),
              const SizedBox(width: 6),
              Text(_app.me?.phoneMasked ?? '', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _useSaved && !_showPhoneField,
            onChanged: (v) => setState(() {
              _useSaved = v ?? false;
              if (v == true) _showPhoneField = false;
            }),
            title: Text(l.raw('lead_use_saved'), style: Theme.of(context).textTheme.bodySmall),
          ),
          if (_useSaved)
            TextButton(
              onPressed: () => setState(() => _showPhoneField = !_showPhoneField),
              child: Text(l.raw('lead_use_other_phone')),
            ),
        ],
      ),
    );
  }
}

/// 成功屏：order_number 为 null 时整行隐藏，不能印一个空（§6.6）。
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.result, required this.title});
  final MarketLeadResult result;
  final String title;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final l = app.l10n;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: MarketTokens.success),
              const SizedBox(width: 8),
              Expanded(child: Text(l.raw('lead_success_title'), style: Theme.of(context).textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted)),
          const SizedBox(height: 12),
          _row(l.fill('lead_quoted', {'a': formatPrice(result.quotedAmount, result.currency)})),
          if (result.quantity != null) _row(l.fill('lead_quantity_result', {'n': result.quantity})),
          _row(l.fill('lead_masked_phone', {'p': result.contactMasked})),
          // contact_masked 是 maskPhone() 的产物，不是买家刚输入的那串；原文只在输入框 state 里，
          // 页面重建之后就没有了——这是设计，不是缺陷（§7.7）。
          if (result.orderNumber != null) _row(l.fill('lead_order_no', {'n': result.orderNumber})),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MarketTokens.surfaceDim, borderRadius: BorderRadius.circular(10)),
            child: Text(result.nextStep, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l.raw('close'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context), child: Text(l.raw('back_home'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String text) => Builder(
        builder: (context) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      );
}
