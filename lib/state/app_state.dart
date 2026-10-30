import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/credential_store.dart';
import '../core/env.dart';
import '../core/l10n.dart';
import '../core/lang_store.dart';
import '../data/buyer_auth_api.dart';
import '../data/market_api.dart';
import '../data/models.dart';
import 'catalog_controller.dart';
import 'products_controller.dart';

/// 会话状态四态而不是「空」（§6.8）：读失败永远不印成「没有记录」。
enum MeStatus { anon, ok, unknown, invalid, expired, suspended }

/// 全局应用状态：两套凭证之一（买家）在这里，租户凭证（bufang.auth / Supabase Bearer）
/// 在本 App 里不存在、也不许出现（§4.7）。
class AppState extends ChangeNotifier {
  AppState._({
    required this.langStore,
    required this.credentials,
    required this.apiClient,
    required this.marketApi,
    required this.buyerAuthApi,
    required this.analytics,
    required String lang,
  }) : _lang = lang {
    analytics.lang = lang;
  }

  static Future<AppState> bootstrap() async {
    final credentials = CredentialStore();
    final ua = Env.userAgent(_platformWord());
    final apiClient = MarketApiClient(userAgent: ua);
    final marketApi = MarketApi(apiClient, credentials);
    final buyerAuthApi = BuyerAuthApi(apiClient, credentials);
    final analytics = Analytics(marketApi);
    final langStore = LangStore();
    final lang = await langStore.resolve();
    final state = AppState._(
      langStore: langStore,
      credentials: credentials,
      apiClient: apiClient,
      marketApi: marketApi,
      buyerAuthApi: buyerAuthApi,
      analytics: analytics,
      lang: lang,
    );
    // 列表与类目状态提升到全局：首页、底部分类弹层、店铺入口读同一份真值。
    state.catalog = CatalogController(state);
    state.products = ProductsController(state);
    await state._restoreWishlist();
    await state._restoreMe();
    return state;
  }

  static String _platformWord() {
    if (Platform.isAndroid) {
      // 归因侧 deviceClassOf() 认 android/iphone/ipad 这几个平台词（§8.4），大小写不敏感。
      return 'Android';
    }
    if (Platform.isIOS) return 'iPhone';
    return Platform.operatingSystem;
  }

  final LangStore langStore;
  final CredentialStore credentials;
  final MarketApiClient apiClient;
  final MarketApi marketApi;
  final BuyerAuthApi buyerAuthApi;
  final Analytics analytics;

  late final CatalogController catalog;
  late final ProductsController products;

  String _lang;
  String get lang => _lang;
  MarketL10n get l10n => MarketL10n(_lang);

  /// 语言变了：类目树、列表、日历分面都要按新 lang 重读——集中一处，不留第二份真值。
  Future<void> setLang(String value) async {
    if (value == _lang) return;
    await langStore.choose(value);
    _lang = await langStore.resolve();
    analytics.lang = _lang;
    notifyListeners();
    catalog.reloadForLang();
    products.refresh();
    products.loadFacet();
  }

  /// 深链/分享链接带 ?lang= 时走这条（不写偏好，只影响本会话，§8.6）。
  Future<void> applyDeepLinkLang(String? value) async {
    if (value == null) return;
    final next = await langStore.resolve(deeplinkLang: value);
    if (next == _lang) return;
    _lang = next;
    analytics.lang = _lang;
    notifyListeners();
    catalog.reloadForLang();
    products.refresh();
    products.loadFacet();
  }

  void setDeviceClass(double shortestWidth) {
    analytics.deviceClass = shortestWidth >= 600 ? 'tablet' : 'mobile';
  }

  // ---------- 登录态 ----------

  MeStatus _meStatus = MeStatus.anon;
  BuyerMe? _me;
  MeStatus get meStatus => _meStatus;
  BuyerMe? get me => _me;
  bool get signedIn => _meStatus == MeStatus.ok && _me != null;

  Future<void> _restoreMe() async {
    final session = await credentials.readSession();
    if (session == null) {
      _meStatus = MeStatus.anon;
      return;
    }
    try {
      _me = await buyerAuthApi.me();
      _meStatus = MeStatus.ok;
      await _syncCloudFavorites();
    } on MarketApiException catch (e) {
      if (e.isSessionBroken) {
        await credentials.clearSession();
        _meStatus = e.code == 'BUYER_SESSION_EXPIRED' ? MeStatus.expired : MeStatus.invalid;
        _me = null;
      } else if (e.isAccountSuspended) {
        _meStatus = MeStatus.suspended;
        _me = null;
      } else {
        // 读失败 ≠ 没登录：保持会话，状态 unknown（个人页显示一行重新登录入口即可）。
        _meStatus = MeStatus.unknown;
      }
    } catch (_) {
      _meStatus = MeStatus.unknown;
    }
  }

  Future<void> refreshMe() async {
    final session = await credentials.readSession();
    if (session == null) {
      _me = null;
      _meStatus = MeStatus.anon;
      notifyListeners();
      return;
    }
    try {
      _me = await buyerAuthApi.me();
      _meStatus = MeStatus.ok;
    } on MarketApiException catch (e) {
      if (e.isSessionBroken) {
        await credentials.clearSession();
        _me = null;
        _meStatus = MeStatus.invalid;
      } else if (e.isAccountSuspended) {
        _me = null;
        _meStatus = MeStatus.suspended;
      }
      // 其余错误：维持上一次读数（读失败不折成「没有记录」）。
    }
    notifyListeners();
  }

  /// 注册成功 = 直接是登录态（服务端在同一支写里签发会话）。
  Future<void> register({required String name, required String phone, required String password, bool? consentMarketing}) async {
    await buyerAuthApi.register(
      name: name,
      phone: phone,
      password: password, // 原文提交：不 trim、不折叠空白
      lang: lang,
      consentMarketing: consentMarketing,
      sessionId: analytics.sessionId,
      deviceClass: analytics.deviceClass,
    );
    _me = await buyerAuthApi.me();
    _meStatus = MeStatus.ok;
    await _migrateLocalFavorites();
    await _syncCloudFavorites();
    notifyListeners();
  }

  Future<void> login({required String phone, required String password}) async {
    await buyerAuthApi.login(phone: phone, password: password, deviceClass: analytics.deviceClass);
    _me = await buyerAuthApi.me();
    _meStatus = MeStatus.ok;
    await _migrateLocalFavorites();
    await _syncCloudFavorites();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await buyerAuthApi.logout(); // finally 里清本地行，由 BuyerAuthApi 保证
    } finally {
      _me = null;
      _meStatus = MeStatus.anon;
      _cloudFavorites.clear();
      notifyListeners();
    }
  }

  String? describeError(Object e) {
    if (e is MarketApiException) return l10n.errorText(e);
    return null;
  }

  // ---------- 收藏：服务端是成员真相，本地是缓存（§6.8）----------

  static const String _localFavKey = 'yuanbao.market.wishlist.local';
  static const String _migratedKey = 'yuanbaokucun.market.wishlist.migrated';
  static const int favoritesMax = 200; // 与 BUYER_FAVORITES_MAX 同值，否则云端装得下、本地装不下

  final Set<String> _localFavorites = {};
  final Set<String> _cloudFavorites = {};
  final Set<String> _migratedSubmitted = {};
  late SharedPreferences _prefs;

  Future<void> _restoreWishlist() async {
    _prefs = await SharedPreferences.getInstance();
    _localFavorites.addAll(_prefs.getStringList(_localFavKey) ?? const []);
    _migratedSubmitted.addAll(_prefs.getStringList(_migratedKey) ?? const []);
  }

  bool isFavorite(String slug) => signedIn ? _cloudFavorites.contains(slug) : _localFavorites.contains(slug);

  Set<String> get favoriteSlugs => signedIn ? Set.unmodifiable(_cloudFavorites) : Set.unmodifiable(_localFavorites);

  /// 登录成功后把本地攒的 slug 交上去——只发差集，且已交过的不再重发。
  Future<void> _migrateLocalFavorites() async {
    final pending = _localFavorites.where((s) => !_migratedSubmitted.contains(s)).toList();
    if (pending.isEmpty) return;
    try {
      await buyerAuthApi.migrateFavorites(pending);
      _migratedSubmitted.addAll(pending);
      await _prefs.setStringList(_migratedKey, _migratedSubmitted.toList());
    } catch (_) {
      // 迁移失败不阻塞登录态；下次登录再补发（已交集合没记，宁可重发——服务端幂等）。
    }
  }

  Future<void> _syncCloudFavorites() async {
    try {
      _cloudFavorites
        ..clear()
        ..addAll(await buyerAuthApi.listFavoriteSlugs());
      notifyListeners();
    } catch (_) {/* 读失败保持上一次集合 */}
  }

  /// 乐观写、失败回滚。remove 对本来不在集合里的 slug 返回 removed:false 且 200——
  /// 「点了没反应」和「本来就没有」在服务端是同一个答案，界面上直接按未收藏画。
  Future<String?> toggleFavorite(String slug) async {
    if (!signedIn) {
      if (_localFavorites.contains(slug)) {
        _localFavorites.remove(slug);
      } else {
        if (_localFavorites.length >= favoritesMax) return l10n.raw('err_favorites_full');
        _localFavorites.add(slug);
      }
      await _prefs.setStringList(_localFavKey, _localFavorites.toList());
      notifyListeners();
      return null;
    }
    final wasFavorited = _cloudFavorites.contains(slug);
    if (!wasFavorited && _cloudFavorites.length >= favoritesMax) return l10n.raw('err_favorites_full');
    if (wasFavorited) {
      _cloudFavorites.remove(slug);
    } else {
      _cloudFavorites.add(slug);
    }
    notifyListeners();
    try {
      if (wasFavorited) {
        await buyerAuthApi.removeFavorite(slug);
        _localFavorites.remove(slug);
        await _prefs.setStringList(_localFavKey, _localFavorites.toList());
      } else {
        await buyerAuthApi.addFavorite(slug, lang);
        if (!_migratedSubmitted.contains(slug)) {
          _migratedSubmitted.add(slug);
          await _prefs.setStringList(_migratedKey, _migratedSubmitted.toList());
        }
        _localFavorites.add(slug); // 本地与云端两边都保持点亮
        await _prefs.setStringList(_localFavKey, _localFavorites.toList());
      }
      return null;
    } on MarketApiException catch (e) {
      // 回滚
      if (wasFavorited) {
        _cloudFavorites.add(slug);
      } else {
        _cloudFavorites.remove(slug);
      }
      notifyListeners();
      return l10n.errorText(e);
    } catch (_) {
      if (wasFavorited) {
        _cloudFavorites.add(slug);
      } else {
        _cloudFavorites.remove(slug);
      }
      notifyListeners();
      return l10n.raw('err_network');
    }
  }
}
