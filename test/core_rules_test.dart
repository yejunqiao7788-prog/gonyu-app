import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_app/core/api_client.dart';
import 'package:market_app/core/api_exception.dart';
import 'package:market_app/core/l10n.dart';
import 'package:market_app/core/lang_store.dart';
import 'package:market_app/data/models.dart';

void main() {
  group('信封与错误分派（§3.2、§5.1）', () {
    test('ok:true 返回 data，query 丢弃空值', () async {
      Uri? seen;
      final client = MarketApiClient(
        client: MockClient((req) async {
          seen = req.url;
          return http.Response(jsonEncode({'ok': true, 'data': {'hello': 1}, 'meta': {'requestId': 'r1'}}), 200);
        }),
      );
      final data = await client.get('/catalog', query: {'lang': 'uk', 'empty': '', 'nul': null});
      expect(data, {'hello': 1});
      expect(seen!.queryParameters, {'lang': 'uk'});
      expect(seen!.path, '/api/market/catalog');
    });

    test('ok:false 按 error.code 抛出，details 与 requestId 保留', () async {
      final client = MarketApiClient(
        client: MockClient((req) async => http.Response(
              jsonEncode({
                'ok': false,
                'error': {'code': 'BELOW_MIN_ORDER', 'message': 'x', 'details': {'min_order_qty': 24}},
                'meta': {'requestId': 'abc'},
              }),
              400,
            )),
      );
      await expectLater(client.get('/products'), throwsA(isA<MarketApiException>()
          .having((e) => e.code, 'code', 'BELOW_MIN_ORDER')
          .having((e) => e.detailNum('min_order_qty'), 'min', 24)
          .having((e) => e.requestId, 'rid', 'abc')));
    });

    test('响应体以 < 开头 = 网关 HTML，不尝试 JSON.parse（§8.1）', () async {
      final client = MarketApiClient(client: MockClient((req) async => http.Response('<html>502</html>', 502)));
      await expectLater(client.get('/products'), throwsA(isA<MarketApiException>().having((e) => e.code, 'code', 'GATEWAY_HTML')));
    });

    test('只重试 GET：写路径 500 也只发一次', () async {
      int calls = 0;
      final client = MarketApiClient(
        client: MockClient((req) async {
          calls++;
          return http.Response(jsonEncode({'ok': false, 'error': {'code': 'CUSTOMER_FAILED'}}), 500);
        }),
      );
      await expectLater(client.post('/leads', body: {'slug': 'x'}), throwsA(isA<MarketApiException>()));
      expect(calls, 1);
    });

    test('GET 对可重试错误退避后成功', () async {
      int calls = 0;
      final client = MarketApiClient(
        client: MockClient((req) async {
          calls++;
          if (calls < 2) return http.Response(jsonEncode({'ok': false, 'error': {'code': 'DB_ERROR'}}), 502);
          return http.Response(jsonEncode({'ok': true, 'data': {'items': []}}), 200);
        }),
      );
      final data = await client.get('/products');
      expect(data, {'items': []});
      expect(calls, 2);
    });
  });

  group('错误分档（§12.2）', () {
    test('会话三码归一句可重试文案；SUSPENDED 单独一档', () {
      final l = MarketL10n('zh');
      for (final code in ['BUYER_LOGIN_REQUIRED', 'BUYER_SESSION_INVALID', 'BUYER_SESSION_EXPIRED']) {
        expect(l.errorText(MarketApiException(status: 401, code: code)), l.raw('err_relogin'));
      }
      expect(l.errorText(MarketApiException(status: 403, code: 'BUYER_ACCOUNT_SUSPENDED')), isNot(l.raw('err_relogin')));
    });

    test('D4：process_order_v2 透传的 message（5xx 且 exposeMessage）原样上屏', () {
      final l = MarketL10n('uk');
      final msg = '库存不足：Пшениця / SKU-1（需要 50，现有 20）';
      expect(l.errorText(MarketApiException(status: 500, code: 'HTTP_500', serverMessage: msg)), msg);
    });

    test('D3：expired 有专门文案，未知状态走默认分支说事实', () {
      final l = MarketL10n('zh');
      expect(l.leadStatusText('expired'), contains('平台自动'));
      expect(l.leadStatusText('weird_future_value'), contains('weird_future_value'));
    });
  });

  group('语言（§5.7、§9.6）', () {
    test('normalize 兜底 uk；en/vi 读英文列', () {
      final store = LangStore();
      expect(store.normalize('de'), 'uk');
      expect(store.normalize('VI'), 'vi');
      expect(store.readsEnglishContent('vi'), true);
      expect(store.readsEnglishContent('uk'), false);
    });
  });

  group('null 纪律与显示（§7.3、§7.8）', () {
    test('formatPrice 千分位与符号前缀，符号来自出参', () {
      expect(formatPrice(1234567.5, r'$'), r'$1,234,567.50');
      expect(formatPrice(500, '€'), '€500');
    });

    test('卡片键的 null 各自保真：sku 空串折回 null、rating null 不折 0', () {
      final card = MarketCard.fromMap({'slug': 's', 'sku': '', 'rating': null, 'lead_time_days': null});
      expect(card.sku, isNull);
      expect(card.rating, isNull);
      expect(card.leadTimeDays, isNull);
      expect(card.imageCount, 0);
    });

    test('分页采纳服务端回显的 page 与 sort', () {
      final page = MarketProductPage.fromMap({'items': [], 'page': 1, 'page_size': 60, 'total': 0, 'total_pages': 1, 'sort': 'recommended'});
      expect(page.page, 1);
      expect(page.sort, 'recommended');
    });

    test('留资成功回参：order_number 为 null 不是失败', () {
      final r = MarketLeadResult.fromMap({'lead_id': 'L1', 'order_number': null, 'quoted_amount': '1250.00', 'currency': r'$', 'contact_masked': '+380****88', 'next_step': 'ns', 'seller_name': 'Agro'});
      expect(r.orderNumber, isNull);
      expect(r.quotedAmount, 1250.0);
      expect(r.contactMasked, '+380****88');
    });

    test('日历 truncated ⇒ 下界语义存在；reason ⇒ 整块不渲染', () {
      final f = MarketListedDayFacet.fromMap({'truncated': true, 'window': {'from': '2026-10-01', 'to': '2026-10-31', 'days': 30}});
      expect(f.truncated, true);
      expect(f.renderable, true);
      final bad = MarketListedDayFacet.fromMap({'reason': 'category_not_found', 'window': null});
      expect(bad.renderable, false);
    });
  });
}
