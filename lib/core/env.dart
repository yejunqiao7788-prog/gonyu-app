/// 环境与端点配置。公域端一个密钥都不需要（文档 §2.3、§9.2）：
/// 全部凭证就是买家登录后拿到的 X-Buyer-Session。
class Env {
  /// 公域集市 API 基址。必须指向 www（不是 app.）——/api/market/* 的同源与限流都挂在这个 host 上。
  static const String apiBase = String.fromEnvironment(
    'MARKET_API_BASE',
    defaultValue: 'https://www.torgseek.com/api/market',
  );

  /// 公域站点基址（分享、打开网页用）。
  static const String siteBase = String.fromEnvironment(
    'MARKET_SITE_BASE',
    defaultValue: 'https://www.torgseek.com',
  );

  static const String appName = 'TorgSeek';
  static const String appVersion = '0.1.0';

  /// User-Agent：必须含平台词（android/iphone/ipad），否则归因侧 deviceClassOf() 只能答 null 或 desktop（§8.4）。
  /// 不要伪造完整浏览器 UA。
  static String userAgent(String platformWord) =>
      'TorgSeekMarketApp/$appVersion ($platformWord)';

  // 超时档位：全文唯一的数字之家是 §3.3/§8.1，App 取浏览器现值为下限。
  static const Duration readTimeout = Duration(seconds: 30);
  static const Duration leadTimeout = Duration(seconds: 45); // 串了 RPC，全文件最长
  static const Duration chatWriteTimeout = Duration(seconds: 20);
  static const Duration chatPollTimeout = Duration(seconds: 15); // 轮询必须快速失败
  static const Duration accountWriteTimeout = Duration(seconds: 20); // 注册/登录/改密/注销
  static const Duration accountReadTimeout = Duration(seconds: 15); // me/登出/个人页读与收藏写
  static const Duration favoriteMigrateTimeout = Duration(seconds: 20);
  static const Duration eventsTimeout = Duration(seconds: 8);
}
