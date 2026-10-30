/// 错误码分派（文档 §5.1、§12.2）：客户端只按 error.code 分支，永不解析 message。
/// 分组标题就是处理策略：同组共用一套 UI 反应，跨组混用会说出假话。
class MarketApiException implements Exception {
  MarketApiException({
    required this.status,
    required this.code,
    this.serverMessage,
    this.details,
    this.requestId,
    this.isNetworkFailure = false,
  });

  factory MarketApiException.network(String code, [Object? cause]) =>
      MarketApiException(status: 0, code: code, serverMessage: '$cause', isNetworkFailure: true);

  final int status;
  final String code;
  final String? serverMessage;
  final Map<String, dynamic>? details;
  final String? requestId;
  final bool isNetworkFailure;

  /// ① 等一下就好（可重试，退避）——只允许打在 GET 上（§5.1）。
  bool get isRateLimited => status == 429 && code == 'RATE_LIMITED';
  bool get isBuyerLoginLocked => code == 'BUYER_LOGIN_LOCKED';
  bool get isUpstreamFailure =>
      status >= 500 || const {'DB_ERROR', 'FETCH_ERROR', 'BUYER_SESSION_FAILED', 'BUYER_LOGIN_FAILED'}.contains(code);
  bool get isGatewayHtml => code == 'GATEWAY_HTML'; // 响应体以 '<' 开头 = 网关 HTML，不是数据（§8.1）

  bool get retryable => isNetworkFailure || isRateLimited || status >= 500;

  /// ② 输入不对：留在当前屏，标红具体字段。
  bool get isInvalidInput => const {
        'INVALID_PHONE',
        'INVALID_NAME',
        'INVALID_PASSWORD',
        'CHAT_EMPTY',
        'BELOW_MIN_ORDER',
        'OVER_STOCK',
      }.contains(code);

  /// ③ 这一格没了：404 给终点态，不给重试。
  bool get isNotFound => status == 404 || const {
        'LISTING_NOT_FOUND',
        'SELLER_NOT_FOUND',
        'CHAT_NOT_FOUND',
        'LEAD_NOT_FOUND',
        'BUYER_ACCOUNT_NOT_FOUND',
        'NOT_FOUND',
      }.contains(code);

  /// ④ 现在不行：可解释，多数不可由用户修复。
  bool get isUnavailableNow => const {
        'CHAT_DISABLED',
        'LISTING_UNAVAILABLE',
        'TENANT_UNAVAILABLE',
        'OUT_OF_STOCK',
        'CHAT_CLOSED',
        'CHAT_BLOCKED',
        'FAVORITES_FULL',
        'BUYER_PHONE_REGISTERED',
        'BUYER_ACCOUNT_CLOSED',
        'CHAT_BANNED_WORD',
      }.contains(code);

  /// ⑤ 凭证问题：唯一一组会影响「登录态」的。
  bool get isLoginRequired => code == 'BUYER_LOGIN_REQUIRED';
  bool get isSessionBroken => const {'BUYER_SESSION_INVALID', 'BUYER_SESSION_EXPIRED'}.contains(code);
  bool get isInvalidCredentials => code == 'BUYER_INVALID_CREDENTIALS';
  bool get isAccountSuspended => code == 'BUYER_ACCOUNT_SUSPENDED';

  /// 429 BUYER_LOGIN_LOCKED 带的账号级事实：用服务端给的秒数倒计时，不要自己数 15 分钟（§4.5）。
  int? get retryAfterSeconds {
    final raw = details?['retry_after_seconds'] ?? details?['retryAfterSeconds'];
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  num? detailNum(String key) {
    final raw = details?[key];
    if (raw is num) return raw;
    return num.tryParse('$raw');
  }

  @override
  String toString() => 'MarketApiException($status $code ${serverMessage ?? ''})'.trim();
}
