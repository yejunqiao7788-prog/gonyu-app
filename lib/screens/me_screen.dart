import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/product_card.dart';
import 'auth_screen.dart';
import 'product_detail_screen.dart';
import 'settings_screen.dart';

/// 个人页四态而不是「空」（§6.8）：
/// logged_out → 登录引导（本地收藏照常可用）；unknown/invalid/expired → 一行重新登录；
/// suspended → 它自己的一句话。读失败永远不印成「没有记录」。
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> with SingleTickerProviderStateMixin {
  late final AppState _app;
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _tabs = TabController(length: 3, vsync: this);
    _app.refreshMe();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.raw('tab_me')),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final l = _app.l10n;
    switch (_app.meStatus) {
      case MeStatus.anon:
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.raw('login_prompt'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(l.raw('favorite_local_note'), style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(initialMode: 'login'))), child: Text(l.raw('login'))),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(initialMode: 'register'))), child: Text(l.raw('register'))),
            const SizedBox(height: 24),
            _localFavoritesBlock(),
          ],
        );
      case MeStatus.unknown:
      case MeStatus.invalid:
      case MeStatus.expired:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.raw('err_relogin')),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(initialMode: 'login'))), child: Text(l.raw('login'))),
            ],
          ),
        );
      case MeStatus.suspended:
        // 被处置的账号：一句话说明，不给重试按钮（§4.5）。
        return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(l.raw('err_suspended'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)));
      case MeStatus.ok:
        return _loggedIn();
    }
  }

  Widget _loggedIn() {
    final l = _app.l10n;
    final me = _app.me;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 注销墓碑 name 为 null：按状态出本地化文案，不打印库里的 'deleted'（§4.8）。
                    Text(me?.name ?? l.raw('buyer_name'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(me?.phoneMasked ?? '', style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
                  ],
                ),
              ),
              // stats 的 null 是「这一格没读到」，画短横，不折成 0——这条病根记过三次（§4.4）。
              _stat(l.raw('me_leads'), me?.stats.leads),
              _stat(l.raw('me_threads'), me?.stats.conversations),
              _stat(l.raw('me_favorites'), me?.stats.favorites),
            ],
          ),
        ),
        TabBar(controller: _tabs, tabs: [Tab(text: l.raw('me_leads')), Tab(text: l.raw('me_threads')), Tab(text: l.raw('me_favorites'))]),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_Pager<BuyerLeadRow>(loader: (p, s) => _app.buyerAuthApi.listLeads(lang: _app.lang, page: p, pageSize: s), build: _leadTile), _Pager<BuyerConversationRow>(loader: (p, s) => _app.buyerAuthApi.listConversations(page: p, pageSize: s), build: _threadTile), _Pager<BuyerFavoriteRow>(loader: (p, s) => _app.buyerAuthApi.listFavorites(lang: _app.lang, page: p, pageSize: s), build: _favoriteTile)],
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, int? value) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        children: [
          value == null ? NullDash(tooltip: _app.l10n.raw('not_loaded')) : Text('$value', style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _localFavoritesBlock() {
    final slugs = _app.favoriteSlugs.toList();
    if (slugs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_app.l10n.raw('me_favorites'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text('${slugs.length} ${_app.l10n.raw('me_favorites')}', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _leadTile(BuildContext context, BuyerLeadRow row) {
    final l = _app.l10n;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(row.listingTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge)),
                _statusChip(row.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(row.sellerName, style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                // 历史留资行可能仍标 'UAH'：拿到什么印什么，不在 App 侧「统一」（§7.4）。
                Text(formatPrice(row.quotedAmount, row.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (row.quantity != null) Text(l.fill('lead_quantity_result', {'n': row.quantity})),
                // order_number 为 null 时整行隐藏。
                if (row.orderNumber != null) Text(l.fill('lead_order_no', {'n': row.orderNumber}), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (row.slug != null && row.listingVisible)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(slug: row.slug!, fromSource: 'detail'))),
                  child: Text(l.raw('open_listing')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final expired = status == 'expired';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // expired 是平台自动判的事实（D3），显示「已过期（平台自动）」，不给任何改状态入口。
        color: expired ? const Color(0xFFF5E9E4) : MarketTokens.surfaceDim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_app.l10n.leadStatusText(status), style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _threadTile(BuildContext context, BuyerConversationRow row) {
    final l = _app.l10n;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text(row.listingTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          row.lastMessage?.body ?? row.sellerName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: row.status != 'open' ? Text(l.raw('chat_closed'), style: Theme.of(context).textTheme.bodySmall) : const Icon(Icons.chevron_right),
        onTap: row.slug == null
            ? null
            : () {
                // conversation_token 是设计出来的出参：用它从个人页续上已有线程，
                // 而不是对同一个商品开第二个线程（§6.8）。
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(slug: row.slug!, fromSource: 'detail', openChat: true, chatToken: row.conversationToken),
                ));
              },
      ),
    );
  }

  Widget _favoriteTile(BuildContext context, BuyerFavoriteRow row) {
    // listing_visible=false ⇒ 渲染这一行但不给链接：它是买家自己的记录，不能从列表里删掉（§6.8）。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ProductCard(
        card: row.card,
        source: 'home',
        view: 'favorites',
        position: 0,
        pageNumber: 1,
        disabled: !row.listingVisible,
        onDisabledTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_app.l10n.raw('listing_unavailable_short')))),
      ),
    );
  }
}

/// 个人页三块共用的分页列表：{items,page,page_size,total} 各读各的、total 是自洽的（§10.7）。
class _Pager<T> extends StatefulWidget {
  const _Pager({required this.loader, required this.build});

  final Future<BuyerPage<T>> Function(int page, int pageSize) loader;
  final Widget Function(BuildContext context, T row) build;

  @override
  State<_Pager<T>> createState() => _PagerState<T>();
}

class _PagerState<T> extends State<_Pager<T>> {
  List<T> rows = [];
  int page = 0;
  int total = 0;
  bool loading = true;
  String? errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => loading = true);
    try {
      final result = await widget.loader(more ? page + 1 : 1, 20);
      setState(() {
        page = result.page;
        total = result.total;
        rows = more ? [...rows, ...result.items] : result.items;
        errorText = null;
      });
    } on MarketApiException catch (e) {
      setState(() => errorText = context.read<AppState>().describeError(e));
    } catch (_) {
      setState(() => errorText = '…');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && rows.isEmpty) return const Center(child: CircularProgressIndicator());
    if (errorText != null && rows.isEmpty) {
      // 读失败 ≠ 没有记录（§7.8）：这一档有自己的重试行。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorText!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(onPressed: _load, child: Text(context.read<AppState>().l10n.raw('retry'))),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(child: Text(context.read<AppState>().l10n.raw('empty_hint'), style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted)));
    }
    return ListView(
      children: [
        for (final row in rows) widget.build(context, row),
        if (rows.length < total)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(onPressed: () => _load(more: true), child: Text(context.read<AppState>().l10n.raw('loading'))),
            ),
          ),
      ],
    );
  }
}
