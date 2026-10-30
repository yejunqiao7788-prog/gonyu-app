import '../core/api_client.dart';
import '../core/credential_store.dart';
import '../core/env.dart';
import 'models.dart';

/// 买家账号 13 条（§4、§6.8）。全部走 X-Buyer-Session，永带 skipAuth 语义——
/// 这条链上没有 Authorization 的位置。传输层形状照抄 src/api/buyerAuth.ts。
class BuyerAuthApi {
  BuyerAuthApi(this._client, this._credentials);

  final MarketApiClient _client;
  final CredentialStore _credentials;

  Future<BuyerAuthResult> register({
    required String name,
    required String phone,
    required String password,
    required String lang,
    bool? consentMarketing,
    required String sessionId,
    required String deviceClass,
  }) async {
    final data = await _client.post('/buyer/register', body: {
      'name': name,
      'phone': phone,
      // 密码原文照抄提交：不 trim、不折叠空白（§4.2）——改了字符就等于换了一个密码。
      'password': password,
      'lang': lang,
      if (consentMarketing != null) 'consent_marketing': consentMarketing,
      'session_id': sessionId,
      'device_class': deviceClass,
    }, timeout: Env.accountWriteTimeout);
    final result = BuyerAuthResult.fromMap(_asMap(data));
    await _credentials.saveSession(result.sessionToken, result.sessionExpiresAt);
    return result;
  }

  Future<BuyerAuthResult> login({
    required String phone,
    required String password,
    required String deviceClass,
  }) async {
    final data = await _client.post('/buyer/login', body: {
      'phone': phone, 'password': password, 'device_class': deviceClass,
    }, timeout: Env.accountWriteTimeout);
    final result = BuyerAuthResult.fromMap(_asMap(data));
    await _credentials.saveSession(result.sessionToken, result.sessionExpiresAt);
    return result;
  }

  /// 静默恢复：失败即「未登录」，由调用方分派 BUYER_SESSION_* 与 SUSPENDED。
  Future<BuyerMe> me() async {
    final data = await _client.get('/buyer/me', headers: await _credentials.buyerHeaders(), timeout: Env.accountReadTimeout);
    return BuyerMe.fromMap(_asMap(data));
  }

  Future<void> logout() async {
    try {
      await _client.post('/buyer/logout', body: const {}, headers: await _credentials.buyerHeaders(), timeout: Env.accountReadTimeout);
    } finally {
      // finally 里清本地行：服务端返回失败也要清。本地留着一条服务端已经不要的凭证，
      // 比强制重登更糟——每次请求都会带一个永远 401 的头（§4.3）。
      await _credentials.clearSession();
    }
  }

  /// 改密不是登出：当前会话继续存活，其他设备会话被吊销（§4.3）。
  Future<({int revokedSessions})> changePassword({required String currentPassword, required String newPassword}) async {
    final data = await _client.post('/buyer/password', body: {
      'current_password': currentPassword, 'new_password': newPassword,
    }, headers: await _credentials.buyerHeaders(), timeout: Env.accountWriteTimeout);
    final m = _asMap(data);
    return (revokedSessions: (m['revoked_sessions'] as num?)?.toInt() ?? 0);
  }

  /// 注销是墓碑不是删除（§4.8）；成功后账号没有个人页可读。
  Future<void> closeAccount({required String currentPassword}) async {
    try {
      await _client.post('/buyer/close', body: {'current_password': currentPassword},
          headers: await _credentials.buyerHeaders(), timeout: Env.accountWriteTimeout);
    } finally {
      await _credentials.clearSession();
    }
  }

  // ---------- 个人页三块 ----------

  Future<BuyerPage<BuyerLeadRow>> listLeads({String? lang, int? page, int? pageSize}) async {
    final data = await _client.get('/buyer/leads',
        query: {'lang': lang, 'page': page, 'page_size': pageSize},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    return BuyerPage.fromMap(_asMap(data), BuyerLeadRow.fromMap);
  }

  Future<BuyerPage<BuyerConversationRow>> listConversations({int? page, int? pageSize}) async {
    final data = await _client.get('/buyer/conversations',
        query: {'page': page, 'page_size': pageSize},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    return BuyerPage.fromMap(_asMap(data), BuyerConversationRow.fromMap);
  }

  Future<BuyerPage<BuyerFavoriteRow>> listFavorites({String? lang, int? page, int? pageSize}) async {
    final data = await _client.get('/buyer/favorites',
        query: {'lang': lang, 'page': page, 'page_size': pageSize},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    return BuyerPage.fromMap(_asMap(data), BuyerFavoriteRow.fromMap);
  }

  /// 成员真相：刻意不做可见性判断——已经点亮的心必须保持点亮（§6.8）。
  Future<List<String>> listFavoriteSlugs() async {
    final data = await _client.get('/buyer/favorites/slugs',
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    final m = _asMap(data);
    return (m['slugs'] as List?)?.map((e) => '$e').toList() ?? const [];
  }

  Future<FavoriteAddResult> addFavorite(String slug, String lang) async {
    final data = await _client.post('/buyer/favorites',
        body: {'slug': slug, 'lang': lang},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    return FavoriteAddResult.fromMap(_asMap(data));
  }

  /// POST favorites/remove，不是 DELETE——CORS 只放 GET/POST/OPTIONS（§5.6）。
  /// 不受可见性门控：已下架商品的收藏必须还能取消，否则那颗心是一个永久谎言。
  Future<FavoriteRemoveResult> removeFavorite(String slug) async {
    final data = await _client.post('/buyer/favorites/remove',
        body: {'slug': slug},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.accountReadTimeout);
    return FavoriteRemoveResult.fromMap(_asMap(data));
  }

  /// 迁移只发差集；一次最多 200 条。
  Future<FavoriteMigrateResult> migrateFavorites(List<String> slugs) async {
    final data = await _client.post('/buyer/favorites/migrate',
        body: {'slugs': slugs},
        headers: await _credentials.buyerHeaders(),
        timeout: Env.favoriteMigrateTimeout);
    return FavoriteMigrateResult.fromMap(_asMap(data));
  }

  static Map<String, dynamic> _asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}
