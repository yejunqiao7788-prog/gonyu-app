import 'api_exception.dart';
import 'l10n_table.dart';

/// 四语取词：行序 [uk,en,zh,vi]，兜底 uk（列 0）——界面显示 A 语言、服务端按 B 语言出文案，
/// 是必须避免的分裂（§5.7），所以 normalize 的兜底与浏览器兜底同为 uk。
class MarketL10n {
  MarketL10n(this.langCode);

  final String langCode;

  int get _index {
    final i = kMarketLangOrder.indexOf(langCode);
    return i < 0 ? 0 : i;
  }

  String raw(String key) {
    final row = kMarketStrings[key];
    if (row == null) return key;
    final value = row[_index];
    if (value.isEmpty) return row[0];
    return value;
  }

  /// {name} 形式占位符。
  String fill(String key, Map<String, Object?> args) {
    var s = raw(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  /// 错误分派表（§12.2）：按 error.code 分组给文案，一个死于会话问题的买家，
  /// 不该被提示「请输入有效手机号」——那等于把平台的登录问题说成用户的输入错误。
  String errorText(MarketApiException e) {
    final d = e.details;
    switch (e.code) {
      case 'BUYER_LOGIN_REQUIRED':
      case 'BUYER_SESSION_INVALID':
      case 'BUYER_SESSION_EXPIRED':
        return raw('err_relogin');
      case 'BUYER_INVALID_CREDENTIALS':
        return raw('err_login_or_register');
      case 'BUYER_ACCOUNT_SUSPENDED':
        return raw('err_suspended');
      case 'BUYER_LOGIN_LOCKED':
        return fill('err_login_locked', {'s': e.retryAfterSeconds ?? 900});
      case 'INVALID_PHONE':
        return raw('err_invalid_phone');
      case 'INVALID_NAME':
        return raw('err_invalid_name');
      case 'INVALID_PASSWORD':
        return raw('err_invalid_password');
      case 'BUYER_PHONE_REGISTERED':
        return raw('err_phone_registered');
      case 'BELOW_MIN_ORDER':
        return fill('err_below_min', {'n': d?['min_order_qty'] ?? '?'});
      case 'OVER_STOCK':
        return fill('err_over_stock', {'n': d?['stock'] ?? '?'});
      case 'OUT_OF_STOCK':
        return raw('err_out_of_stock');
      case 'LISTING_UNAVAILABLE':
        return raw('err_listing_unavailable');
      case 'TENANT_UNAVAILABLE':
        return raw('err_tenant_unavailable');
      case 'CHAT_BANNED_WORD':
        return raw('err_banned_word');
      case 'CHAT_EMPTY':
        return raw('err_chat_empty');
      case 'FAVORITES_FULL':
        return raw('err_favorites_full');
      case 'LISTING_NOT_FOUND':
        return raw('detail_offline_title');
      case 'RATE_LIMITED':
        return raw('err_rate_limited');
      case 'NETWORK':
      case 'TIMEOUT':
        return raw('err_network');
      case 'PRODUCT_UNAVAILABLE':
      case 'CUSTOMER_FAILED':
        // 留资第 10 步之外最常见的 500：可重试的服务端问题。
        return fill('err_generic', {'r': e.requestId == null ? '' : '(${e.requestId})'});
      default:
        // D4：process_order_v2 的库存不足文案是唯一保留上游 message 回显的地方——
        // 服务端标了可展示就原样上屏，不翻译、不改写成通用「提交失败」。
        if (e.status >= 500 && e.serverMessage != null && e.serverMessage!.isNotEmpty) {
          return e.serverMessage!;
        }
        return fill('err_generic', {'r': e.requestId == null ? '' : '(${e.requestId})'});
    }
  }

  /// 留资状态词表外的值（如 expired 之外的新值）必须走默认分支说事实，
  /// 而不是空白 chip 或 Unknown（D3）。
  String leadStatusText(String status) {
    switch (status) {
      case 'new':
        return raw('lead_status_new');
      case 'contacted':
        return raw('lead_status_contacted');
      case 'ordered':
        return raw('lead_status_ordered');
      case 'completed':
        return raw('lead_status_completed');
      case 'declined':
        return raw('lead_status_declined');
      case 'expired':
        return raw('lead_status_expired');
      default:
        return fill('lead_status_raw', {'s': status});
    }
  }

  List<String> get langs => kMarketLangOrder;
}
