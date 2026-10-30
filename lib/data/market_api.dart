import '../core/api_client.dart';
import '../core/credential_store.dart';
import '../core/env.dart';
import 'models.dart';

/// 一条埋事件（八类词表之外的值服务端会 400 UNKNOWN_EVENT，App 不新增词表）。
class MarketEventRow {
  MarketEventRow({
    required this.type,
    this.listingSlug,
    this.sellerSlug,
    this.categorySlug,
    this.position,
    this.page,
    this.source,
    this.query,
    this.sort,
  });
  final String type;
  final String? listingSlug;
  final String? sellerSlug;
  final String? categorySlug;
  final int? position; // 0..200
  final int? page; // 1..500
  final String? source; // home|search|category|seller|related|detail，词表外服务端折 null
  final String? query;
  final String? sort;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (listingSlug != null) 'listing_slug': listingSlug,
        if (sellerSlug != null) 'seller_slug': sellerSlug,
        if (categorySlug != null) 'category_slug': categorySlug,
        if (position != null) 'position': position,
        if (page != null) 'page': page,
        if (source != null) 'source': source,
        if (query != null) 'query': query,
        if (sort != null) 'sort': sort,
      };
}

/// 列表查询参数（§6.2）。参数名以服务端实际接受为准：min_price/max_price。
class MarketQuery {
  MarketQuery({
    this.q,
    this.category,
    this.sort,
    this.minPrice,
    this.maxPrice,
    this.onlinePay,
    this.inStock,
    this.leadTimeMax,
    this.seller,
    this.listedDay,
    this.listedFrom,
    this.listedTo,
    this.listedRecent,
    this.page,
    this.pageSize,
    this.lang,
  });

  final String? q;
  final String? category; // slug
  final String? sort; // 未知值服务端回落 recommended 并回显生效值
  final num? minPrice;
  final num? maxPrice;
  final bool? onlinePay;
  final bool? inStock; // 只有 'true' 生效
  final num? leadTimeMax;
  final String? seller; // 是 slug，不是店名
  final String? listedDay; // 优先级 day > range > recent
  final String? listedFrom;
  final String? listedTo;
  final num? listedRecent;
  final int? page;
  final int? pageSize; // 服务端折进 [1,60]
  final String? lang;

  Map<String, dynamic> toQuery() => {
        if (q != null && q!.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        if (sort != null) 'sort': sort,
        if (minPrice != null) 'min_price': minPrice,
        if (maxPrice != null) 'max_price': maxPrice,
        if (onlinePay == true) 'online_pay': 'true',
        if (inStock == true) 'in_stock': 'true',
        if (leadTimeMax != null) 'lead_time_max': leadTimeMax,
        if (seller != null) 'seller': seller,
        if (listedDay != null) 'listed_day': listedDay,
        if (listedFrom != null) 'listed_from': listedFrom,
        if (listedTo != null) 'listed_to': listedTo,
        if (listedRecent != null) 'listed_recent': listedRecent,
        if (page != null) 'page': page,
        if (pageSize != null) 'page_size': pageSize,
        if (lang != null) 'lang': lang,
      };
}

/// /api/market/* 客户端。动词只有 GET 与 POST（§5.6）：没有 PUT/PATCH/DELETE 路由，
/// 写成 DELETE 会得到 404 NOT_FOUND 而不是「方法不允许」。
class MarketApi {
  MarketApi(this._client, this._credentials);

  final MarketApiClient _client;
  final CredentialStore _credentials;

  // ---------- 公开读（无凭证）----------

  Future<MarketCatalog> getCatalog(String lang) async {
    final data = await _client.get('/catalog', query: {'lang': lang});
    return MarketCatalog.fromMap(_asMap(data));
  }

  Future<MarketProductPage> listProducts(MarketQuery query) async {
    final data = await _client.get('/products', query: query.toQuery());
    return MarketProductPage.fromMap(_asMap(data));
  }

  Future<MarketListedDayFacet> getListedDays(MarketQuery query) async {
    final q = query.toQuery()..remove('page')..remove('page_size');
    final data = await _client.get('/listed-days', query: q);
    return MarketListedDayFacet.fromMap(_asMap(data));
  }

  Future<MarketProductDetail> getProduct(String slug, String lang) async {
    final data = await _client.get('/products/${Uri.encodeComponent(slug)}', query: {'lang': lang});
    return MarketProductDetail.fromMap(_asMap(data));
  }

  Future<MarketSellerPage> getSellerProducts(String slug, {int? page, int? pageSize, bool? inStock, required String lang}) async {
    final data = await _client.get('/sellers/${Uri.encodeComponent(slug)}', query: {
      'page': page, 'page_size': pageSize, if (inStock == true) 'in_stock': 'true', 'lang': lang,
    });
    return MarketSellerPage.fromMap(_asMap(data));
  }

  // ---------- 留资（唯一会真写卖家业务表的买家端点，绝不自动重试）----------

  /// 请求体里没有金额字段可以提交：单价与库存都来自服务端（§7.3、§6.6）。
  /// 已登录买家走「用我的号码」时只带 use_saved_contact: true，不带任何号码字节。
  Future<MarketLeadResult> submitLead({
    required String slug,
    String? phone,
    String? name,
    String? email,
    int? quantity,
    int? boxCount,
    int? pieceCount,
    String? demandNote,
    bool? consentMarketing,
    bool? useSavedContact,
    required String lang,
    required String sessionId,
  }) async {
    final data = await _client.post('/leads', body: {
      'slug': slug,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (quantity != null) 'quantity': quantity,
      if (boxCount != null) 'box_count': boxCount,
      if (pieceCount != null) 'piece_count': pieceCount,
      if (demandNote != null && demandNote.isNotEmpty) 'demand_note': demandNote,
      if (consentMarketing != null) 'consent_marketing': consentMarketing,
      if (useSavedContact == true) 'use_saved_contact': true,
      'lang': lang,
      'session_id': sessionId,
    }, headers: await _credentials.buyerHeaders(), timeout: Env.leadTimeout);
    return MarketLeadResult.fromMap(_asMap(data));
  }

  // ---------- 客服 ----------

  Future<MarketChatState> startChat({required String slug, required String message, required String lang, required String sessionId}) async {
    final data = await _client.post('/chat', body: {
      'slug': slug, 'message': message, 'lang': lang, 'session_id': sessionId,
    }, headers: await _credentials.buyerHeaders(), timeout: Env.chatWriteTimeout);
    return MarketChatState.fromMap(_asMap(data));
  }

  /// 唯一不带凭证的客服读：凭 token 就能读自己的线程（§6.7）。after 游标而不是偏移。
  Future<MarketChatState> getChat(String token, {int? afterId}) async {
    final data = await _client.get('/chat/${Uri.encodeComponent(token)}',
        query: {if (afterId != null && afterId > 0) 'after': afterId}, timeout: Env.chatPollTimeout);
    return MarketChatState.fromMap(_asMap(data));
  }

  Future<MarketChatAppendResult> sendChatMessage(String token, String message, String lang) async {
    final data = await _client.post('/chat/${Uri.encodeComponent(token)}/messages', body: {
      'message': message, 'lang': lang,
    }, headers: await _credentials.buyerHeaders(), timeout: Env.chatWriteTimeout);
    return MarketChatAppendResult.fromMap(_asMap(data));
  }

  // ---------- 埋点（自家度量通道，与广告平台回传是两条独立的路，§9.5）----------

  Future<({int recorded, int skipped})> postEvents({
    required String sessionId,
    required List<MarketEventRow> events,
    required String deviceClass,
    required String lang,
  }) async {
    final data = await _client.post('/events', body: {
      'session_id': sessionId,
      'events': events.map((e) => e.toJson()).toList(),
      'device_class': deviceClass, // mobile|desktop|tablet，客户端自报这把尺（§8.4）
      'lang': lang,
    }, timeout: Env.eventsTimeout);
    final m = _asMap(data);
    return (recorded: (m['recorded'] as num?)?.toInt() ?? 0, skipped: (m['skipped'] as num?)?.toInt() ?? 0);
  }

  static Map<String, dynamic> _asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
}
