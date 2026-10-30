import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 买家凭证在设备上的形状（文档 §8.2、§8.3）：
/// - 真相在服务端（mp_buyer_sessions 行，30 天 TTL），设备只保管凭证。
/// - 存 Keystore / Keychain，不是明文偏好——拿到它就能以这个人身份读写留资、会话、收藏。
/// - 读的时候自逐出：过期就删掉并按「未登录」返回；过期判断只是省一次请求，不是鉴权。
/// - 两个长度：>80 服务端会静默截断成注定 401 的值 → 本地就当没登录；<20 服务端按没带凭证处理 → 同上。
/// - 永不与库存端互换：这里不出现 Authorization/Bearer，也不出现 bufang.auth。
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String sessionKey = 'yuanbao.market.buyer.session';
  static const String chatKey = 'yuanbao.market.chat';

  // ---- 买家会话 ----

  Future<BuyerSession?> readSession() async {
    try {
      final raw = await _storage.read(key: sessionKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final token = '${map['token'] ?? ''}';
      final expiresAt = DateTime.tryParse('${map['expires_at'] ?? ''}');
      if (token.isEmpty) return null;
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        await clearSession(); // 自逐出，不发一次注定 401 的请求
        return null;
      }
      // 长度守卫（§8.3）：逼近服务端 80 字符截断线的值是数据面问题，按未登录处理。
      if (token.length > 80 || token.length < 20) {
        await clearSession();
        return null;
      }
      return BuyerSession(token: token, expiresAt: expiresAt);
    } catch (_) {
      // 读不到就当没登录，不是读失败页面崩。
      return null;
    }
  }

  Future<void> saveSession(String token, String expiresAt) async {
    try {
      await _storage.write(
        key: sessionKey,
        value: jsonEncode({'token': token, 'expires_at': expiresAt}),
      );
    } catch (_) {
      // 写不进是常态（权限被收走等），页面退化为「未登录」而不是崩。
    }
  }

  Future<void> clearSession() async {
    try {
      await _storage.delete(key: sessionKey);
    } catch (_) {/* 吞掉：清不掉也要按未登录走 */}
  }

  /// X-Buyer-Session 的唯一构造点（对应 web 侧 buyerHeaders()）。
  /// 公域端永远不带 Authorization。
  Future<Map<String, String>> buyerHeaders() async {
    final session = await readSession();
    if (session == null) return const {};
    return {'X-Buyer-Session': session.token};
  }

  // ---- 客服线程 token（线程寻址凭证，与会话凭证是两个东西，分开存两处，§8.3）----

  /// {slug: conversation_token}
  Future<Map<String, String>> readChatTokens() async {
    try {
      final raw = await _storage.read(key: chatKey);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<String?> chatTokenFor(String slug) async {
    final map = await readChatTokens();
    return map[slug];
  }

  Future<void> rememberChatToken(String slug, String conversationToken) async {
    try {
      final map = await readChatTokens();
      map[slug] = conversationToken;
      await _storage.write(key: chatKey, value: jsonEncode(map));
    } catch (_) {}
  }

  /// 会话失效时清掉线程映射之外的东西？不——线程 token 不随买家会话失效，
  /// 「继续对话」凭 token 就能读（§6.7：getMarketChat 是唯一不带凭证的客服读）。
}

class BuyerSession {
  BuyerSession({required this.token, required this.expiresAt});
  final String token;
  final DateTime? expiresAt;
}
