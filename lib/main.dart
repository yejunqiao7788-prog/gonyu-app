import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/me_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/seller_screen.dart';
import 'state/app_state.dart';
import 'widgets/category_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Boot());
}

class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  AppState? _state;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    AppState.bootstrap().then((s) {
      if (mounted) setState(() => _state = s);
    }).catchError((Object e) {
      // 冷启动读不到本地凭证按「未登录」走；只有真崩了才显示启动错误。
      if (mounted) setState(() => _bootError = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return MaterialApp(
        theme: MarketTokens.light(),
        home: Scaffold(body: Center(child: _bootError == null ? const CircularProgressIndicator() : Text(_bootError!))),
      );
    }
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          theme: MarketTokens.light(),
          locale: Locale(app.lang),
          supportedLocales: const [Locale('uk'), Locale('en'), Locale('zh'), Locale('vi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const RootShell(),
        ),
      ),
    );
  }
}

/// 壳层：集市 / 分类（底部中间凸起按钮）/ 我的。
/// 返回按钮的原生等价物就是导航栈本身——栈里有站内上一页就弹栈；
/// 没有就落回集市（§8.6）。不要为「记住筛选」伪造历史。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  Future<void> _openCategories() async {
    final app = context.read<AppState>();
    final applied = await showCategorySheet(context);
    if (applied) setState(() => _index = 0);
    if (mounted) app.analytics.flush();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        // device_class 由 App 自报（事件那把尺允许 tablet；归因 UA 那把尺不允许，§8.4）。
        app.setDeviceClass(constraints.biggest.shortestSide);
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              Navigator(
                onGenerateRoute: (settings) => MaterialPageRoute(
                  settings: settings,
                  builder: (_) => _StackEntry(entry: _DeepLink.fromUri(settings.name)),
                ),
              ),
              // 中间键不开独立页：它弹出类目面板，选择后回到集市那一屏。
              const SizedBox.shrink(),
              const MeScreen(),
            ],
          ),
          bottomNavigationBar: _CenterCategoryBar(
            index: _index,
            categoryActive: app.products.category != null,
            marketLabel: l.raw('tab_market'),
            categoriesLabel: l.raw('tab_categories'),
            meLabel: l.raw('tab_me'),
            onTapMarket: () => setState(() => _index = 0),
            onTapCategories: _openCategories,
            onTapMe: () => setState(() => _index = 2),
          ),
        );
      },
    );
  }
}

/// 三键底栏，中间是凸起的圆形「分类」按钮（微信小店式）。
class _CenterCategoryBar extends StatelessWidget {
  const _CenterCategoryBar({
    required this.index,
    required this.categoryActive,
    required this.marketLabel,
    required this.categoriesLabel,
    required this.meLabel,
    required this.onTapMarket,
    required this.onTapCategories,
    required this.onTapMe,
  });

  final int index;
  final bool categoryActive;
  final String marketLabel;
  final String categoriesLabel;
  final String meLabel;
  final VoidCallback onTapMarket;
  final VoidCallback onTapCategories;
  final VoidCallback onTapMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: MarketTokens.surface,
        border: Border(top: BorderSide(color: MarketTokens.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _SideItem(
                icon: index == 0 ? Icons.storefront : Icons.storefront_outlined,
                label: marketLabel,
                active: index == 0,
                onTap: onTapMarket,
              ),
            ),
            SizedBox(
              width: 88,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: -18,
                    child: GestureDetector(
                      onTap: onTapCategories,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF7A5C), MarketTokens.primary],
                              ),
                              boxShadow: [
                                BoxShadow(color: MarketTokens.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            categoriesLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: categoryActive ? MarketTokens.primary : MarketTokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (categoryActive)
                    Positioned(
                      top: -22,
                      right: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: MarketTokens.success, shape: BoxShape.circle, border: Border.all(color: MarketTokens.surface, width: 2)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _SideItem(
                icon: index == 2 ? Icons.person : Icons.person_outline,
                label: meLabel,
                active: index == 2,
                onTap: onTapMe,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: active ? MarketTokens.primary : MarketTokens.muted),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? MarketTokens.primary : MarketTokens.muted)),
        ],
      ),
    );
  }
}

/// 内层导航：深链（分享/落地承接）直接落在详情页或店铺页时，站内没有上一页——
/// 返回动作就是回集市，而不是把用户甩出站。
class _StackEntry extends StatelessWidget {
  const _StackEntry({required this.entry});
  final _DeepLink? entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const HomeScreen();
    if (e.productSlug != null) return ProductDetailScreen(slug: e.productSlug!, fromSource: 'home');
    if (e.sellerSlug != null) return SellerScreen(sellerSlug: e.sellerSlug!);
    return HomeScreen(initialSeller: e.sellerFilter);
  }
}

class _DeepLink {
  _DeepLink._({this.productSlug, this.sellerSlug, this.sellerFilter, this.lang, this.openChat});

  final String? productSlug;
  final String? sellerSlug;
  final String? sellerFilter;
  final String? lang;
  final bool? openChat;

  /// 形如 torgseek://market/p/{slug}?lang=..&chat=open、torgseek://market/s/{seller}、torgseek://market?seller={slug}&lang=..
  static _DeepLink? fromUri(String? name) {
    if (name == null || name.isEmpty || name == '/') return null;
    try {
      final uri = Uri.parse(name.startsWith('torgseek') ? name : 'torgseek://market');
      final segs = uri.pathSegments;
      final lang = uri.queryParameters['lang'];
      final chat = uri.queryParameters['chat'] == 'open';
      final sellerParam = uri.queryParameters['seller'];
      if (segs.length >= 3 && segs[0] == 'market' && segs[1] == 'p') {
        return _DeepLink._(productSlug: segs[2], lang: lang, openChat: chat ? true : null);
      }
      if (segs.length >= 3 && segs[0] == 'market' && segs[1] == 's') {
        return _DeepLink._(sellerSlug: segs[2], lang: lang);
      }
      if (segs.isNotEmpty && segs[0] == 'market') {
        return _DeepLink._(sellerFilter: sellerParam, lang: lang);
      }
      return _DeepLink._(sellerFilter: sellerParam, lang: lang);
    } catch (_) {
      return null;
    }
  }
}
