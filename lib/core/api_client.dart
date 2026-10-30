import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'env.dart';

/// 公域集市传输层：信封解析、按 code 分派、只给 GET 退避重试、网关 HTML 检测、逐端点超时。
///
/// 铁律（§3.2、§5.1、§8.1）：
/// - 客户端只按 error.code 分支；message 是给人看的，不解析。
/// - 只重试 GET，写路径永不自动重试——一次成功的 /leads 在卖家 orders 里是一张真订单。
/// - 响应体以 '<' 开头 = 网关返回了 HTML，按「服务端不可用」处理，不当 JSON 解析。
/// - 公域端永远不带 Authorization；X-Buyer-Session 由 buyerHeaders() 单点注入。
class MarketApiClient {
  MarketApiClient({http.Client? client, this.userAgent})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String? userAgent;

  static final Random _rng = Random.secure();
  static String newRequestId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Uri _uri(String path, Map<String, dynamic>? query) {
    final Uri base = Uri.parse('${Env.apiBase}$path');
    if (query == null || query.isEmpty) return base;
    final clean = <String, String>{};
    query.forEach((k, v) {
      if (v == null) return;
      final s = v is bool ? (v ? 'true' : '') : '$v';
      if (s.isEmpty) return; // undefined/null/'' 一律丢弃，与 web 侧 apiCall 同形
      clean[k] = s;
    });
    return base.replace(queryParameters: {...base.queryParameters, ...clean});
  }

  /// 返回信封里的 data（Map 或 List）；失败抛 MarketApiException。
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? headers,
    Duration timeout = Env.readTimeout,
  }) async {
    final bool isGet = method == 'GET';
    final maxAttempts = isGet ? 3 : 1; // 退避只打在幂等读上
    Object? lastError;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await _send(method, path, query: query, body: body, headers: headers, timeout: timeout);
      } on MarketApiException catch (e) {
        lastError = e;
        if (!isGet || !e.retryable || attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      } catch (e) {
        lastError = e;
        if (!isGet || attempt == maxAttempts - 1) break;
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    if (lastError is MarketApiException) throw lastError;
    throw MarketApiException.network('NETWORK', lastError);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers.addAll({
      'Accept': 'application/json',
      'X-Request-Id': newRequestId(),
      if (userAgent != null) 'User-Agent': userAgent!,
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    });
    if (body != null) request.body = jsonEncode(body);

    late final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw MarketApiException.network('TIMEOUT');
    } catch (e) {
      throw MarketApiException.network('NETWORK', e);
    }

    final raw = utf8.decode(response.bodyBytes);
    final trimmed = raw.trimLeft();
    if (trimmed.startsWith('<')) {
      // 网关错误页（Cloudflare/Vercel SPA 兜底都会这样），不是业务数据。
      throw MarketApiException(
        status: response.statusCode,
        code: response.statusCode == 401 ? 'UNAUTHORIZED' : 'GATEWAY_HTML',
        serverMessage: 'gateway returned html',
      );
    }

    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      throw MarketApiException(status: response.statusCode, code: 'BAD_JSON', serverMessage: raw.length > 200 ? raw.substring(0, 200) : raw);
    }

    if (parsed is Map<String, dynamic>) {
      final ok = parsed['ok'];
      final error = parsed['error'];
      if (ok == false && error is Map<String, dynamic>) {
        final meta = parsed['meta'];
        throw MarketApiException(
          status: response.statusCode,
          code: '${error['code'] ?? 'HTTP_${response.statusCode}'}',
          serverMessage: error['message'] as String?,
          details: error['details'] is Map<String, dynamic> ? Map<String, dynamic>.from(error['details'] as Map) : null,
          requestId: meta is Map<String, dynamic> ? meta['requestId'] as String? : null,
        );
      }
      if (ok == true) return parsed['data'];
      // 5xx 但没标 exposeMessage 的会塌成通用错误；status 非 2xx 一律抛。
      if (response.statusCode >= 400) {
        throw MarketApiException(
          status: response.statusCode,
          code: 'HTTP_${response.statusCode}',
          serverMessage: error is Map ? '${error['message']}' : null,
        );
      }
      return parsed;
    }
    return parsed;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query, Map<String, String>? headers, Duration timeout = Env.readTimeout}) =>
      request('GET', path, query: query, headers: headers, timeout: timeout);

  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers, Duration timeout = Env.accountWriteTimeout}) =>
      request('POST', path, body: body, headers: headers, timeout: timeout);
}
