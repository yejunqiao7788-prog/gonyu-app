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

/// 三键底栏：顶边挖半圆凹槽，中间「分类」圆钮沉进槽里（微信小店式）。
/// 凹槽与圆钮共用一套几何参数，改一处即可整体跟随（见 _BarGeometry）。
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

  // 圆钮直径。凹槽 = 直径 + 一圈缝，圆钮 = 大部分沉在槽内、少量上浮。
  static const double _fabDiameter = 54;

  @override
  Widget build(BuildContext context) {
    final overhang = _BarGeometry.overhang; // 槽上方留给圆钮上浮的空间
    final barHeight = _BarGeometry.barHeight;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox(
      height: overhang + barHeight + safeBottom,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cx = constraints.maxWidth / 2;
          final fabCenter = _BarGeometry.fabCenterY(overhang);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 1) 带凹槽的栏体（顶边在 overhang 处）。
              Positioned(
                top: overhang,
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomPaint(
                  painter: _NotchedBarPainter(cx: cx),
                  size: Size(constraints.maxWidth, barHeight + safeBottom),
                ),
              ),
              // 2) 左右两个入口 + 中间留给圆钮的空位。
              Positioned(
                top: overhang,
                left: 0,
                right: 0,
                height: barHeight,
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
                    const SizedBox(width: 96), // 中间空位 = 凹槽宽度
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
              // 3) 圆钮本体（带一圈柔光阴影，压在凹槽上）。
              Positioned(
                left: cx - _fabDiameter / 2,
                top: fabCenter - _fabDiameter / 2,
                child: GestureDetector(
                  onTap: onTapCategories,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedScale(
                    scale: categoryActive ? 1.04 : 1.0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      width: _fabDiameter,
                      height: _fabDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF7A5C), MarketTokens.primary],
                        ),
                        boxShadow: [
                          BoxShadow(color: MarketTokens.primary.withValues(alpha: 0.30), blurRadius: 14, spreadRadius: 1, offset: const Offset(0, 5)),
                          BoxShadow(color: MarketTokens.surface.withValues(alpha: 1), blurRadius: 0, spreadRadius: 3), // 与凹槽之间的一圈白缝
                        ],
                      ),
                      child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 27),
                    ),
                  ),
                ),
              ),
              // 4) 选中类目时右上角一枚小绿点。
              if (categoryActive)
                Positioned(
                  left: cx + _fabDiameter / 2 - 12,
                  top: fabCenter - _fabDiameter / 2 - 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: MarketTokens.success, shape: BoxShape.circle, border: Border.all(color: MarketTokens.surface, width: 2)),
                  ),
                ),
              // 5) 「分类」标签：贴在圆钮正下方、栏体内。
              Positioned(
                left: cx - 48,
                right: cx - 48,
                top: fabCenter + _fabDiameter / 2 + 3,
                child: IgnorePointer(
                  child: Text(
                    categoriesLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: categoryActive ? MarketTokens.primary : MarketTokens.muted,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 凹槽底栏的几何：一处定义、多处共用，避免圆钮与凹槽错位。
class _BarGeometry {
  static const double overhang = 18.0; // 槽上方留给圆钮上浮的高度
  static const double barHeight = 58.0; // 栏体高度（不含 safeBottom）
  static const double fabDiameter = 54.0;
  static const double notchMargin = 6.0; // 圆钮与凹槽之间的缝
  static const double sink = 12.0; // 圆钮中心相对栏顶下沉量 → 越多越「嵌进槽里」

  static double notchRadius() => fabDiameter / 2 + notchMargin;

  /// 圆钮中心 y（整块 SizedBox 坐标）。栏顶在 overhang，中心再下沉 sink。
  static double fabCenterY(double overhangPx) => overhangPx + sink;
}

/// 画带半圆凹槽的底栏体：圆角矩形减去一个开口的圆（Path.combine difference）。
class _NotchedBarPainter extends CustomPainter {
  _NotchedBarPainter({required this.cx});
  final double cx;

  @override
  void paint(Canvas canvas, Size size) {
    final r = _BarGeometry.notchRadius();
    // 圆槽中心在栏体顶边（y=0），故槽口向上开口、向内凹 r。
    final bar = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, size.width, size.height),
      ));
    final notch = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, 0), radius: r));
    final body = Path.combine(PathOperation.difference, bar, notch);

    // 柔和顶部阴影。
    canvas.drawShadow(
      Path.combine(PathOperation.union, bar, notch),
      Colors.black.withValues(alpha: 0.18),
      3,
      false,
    );
    canvas.drawPath(body, Paint()..color = MarketTokens.surface);
    // 描一条上沿细线（含凹槽边缘），让形状更清晰。
    final border = Paint()
      ..color = MarketTokens.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(body, border);
  }

  @override
  bool shouldRepaint(covariant _NotchedBarPainter oldDelegate) => oldDelegate.cx != cx;
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
