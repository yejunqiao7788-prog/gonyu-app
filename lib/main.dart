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

/// 三键底栏（移植自库存端 ThumbBar，业主 2026-10-31 指定参照）：
/// 凹槽用三次贝塞尔平滑曲线画进栏体顶边，「分类」动作键 Column 随 Row 布局自然落进槽里——
/// 不再是手工 Positioned 对齐两套坐标；选中项在图标下铺一颗浅色胶囊。
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

  static const double _barHeight = 66;
  static const double _notch = 30;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: _barHeight + _notch + safeBottom,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: safeBottom,
            child: CustomPaint(
              painter: _NotchPainter(surface: MarketTokens.surface),
              child: const SizedBox(height: _barHeight + _notch, width: double.infinity),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: safeBottom + 4,
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    icon: Icons.storefront_outlined,
                    activeIcon: Icons.storefront_rounded,
                    label: marketLabel,
                    selected: index == 0,
                    onTap: onTapMarket,
                  ),
                ),
                _ActionKey(
                  label: categoriesLabel,
                  active: categoryActive,
                  onTap: onTapCategories,
                ),
                Expanded(
                  child: _TabButton(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: meLabel,
                    selected: index == 2,
                    onTap: onTapMe,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 三格同高；标签全部贴底同一行 → 中间「分类」与两侧文字基线对齐。
  static const double cellHeight = 58;

  @override
  Widget build(BuildContext context) {
    final color = selected ? MarketTokens.primary : MarketTokens.muted;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: cellHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 12, vertical: 5),
              decoration: BoxDecoration(
                // 选中项：图标底铺一颗品牌色浅胶囊（库存端同款形状）。
                color: selected ? MarketTokens.primary.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(selected ? activeIcon : icon, size: 22, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const double _diameter = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: _TabButton.cellHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 标签与两侧 tab 占同一底部行，字号/字重/颜色档位一致。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: active ? MarketTokens.primary : MarketTokens.muted,
              ),
            ),
          ),
          // 圆钮上浮进凹槽（clip none 允许越过本格顶边）。
          Positioned(
            bottom: 20,
            left: (92 - _diameter) / 2,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: _diameter,
                      height: _diameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF7A5C), MarketTokens.primary],
                        ),
                        boxShadow: [
                          BoxShadow(color: MarketTokens.primary.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.grid_view_rounded, color: Colors.white, size: active ? 26 : 28),
                    ),
                    if (active)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(color: MarketTokens.success, shape: BoxShape.circle, border: Border.all(color: MarketTokens.surface, width: 2)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 中间挖一个圆凹槽，动作键坐进去，视觉上和导航条一体（库存端 _NotchPainter 同款曲线）。
class _NotchPainter extends CustomPainter {
  _NotchPainter({required this.surface});

  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final notchCenterX = size.width / 2;
    final barTop = _notchDepth;
    const radius = 30.0;

    final path = Path()
      ..moveTo(0, barTop)
      ..lineTo(notchCenterX - radius - 14, barTop)
      ..cubicTo(
        notchCenterX - radius + 2,
        barTop,
        notchCenterX - radius + 6,
        barTop + radius * 0.9,
        notchCenterX,
        barTop + radius * 0.9,
      )
      ..cubicTo(
        notchCenterX + radius - 6,
        barTop + radius * 0.9,
        notchCenterX + radius - 2,
        barTop,
        notchCenterX + radius + 14,
        barTop,
      )
      ..lineTo(size.width, barTop)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..color = MarketTokens.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  static const double _notchDepth = 30;

  @override
  bool shouldRepaint(_NotchPainter oldDelegate) => oldDelegate.surface != surface;
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
