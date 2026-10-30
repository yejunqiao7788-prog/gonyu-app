import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/me_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/seller_screen.dart';
import 'state/app_state.dart';

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

/// 两 tab 壳：浏览与个人页。返回按钮的原生等价物就是导航栈本身——
/// 栈里有站内上一页就弹栈；没有就落回集市首页（§8.6）。不要为「记住筛选」伪造历史。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

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
              const MeScreen(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront), label: l.raw('tab_market')),
              NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: l.raw('tab_me')),
            ],
          ),
        );
      },
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
