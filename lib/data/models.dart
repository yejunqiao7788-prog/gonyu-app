/// 出参模型：键集以服务端出参为准，不在 App 里扩（§12.4）。
/// `?` 字段的 null 与 0/'' 是不同事实（§7.8）：null 走「整行隐藏」或「未取到」，0 走「真的是零」。
library;

int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double? _numOrNull(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
bool _boolOf(Object? v) => v == true || v == 'true';
String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _mapList(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];

// ---------- 卡片与列表 ----------

class MarketCard {
  MarketCard.fromMap(Map<String, dynamic> m)
      : slug = '${m['slug'] ?? ''}',
        sellerSlug = _strOrNull(m['seller_slug']),
        sellerName = '${m['seller_name'] ?? ''}',
        title = '${m['title'] ?? ''}',
        sku = _strOrNull(m['sku']), // null=还没有编码 → 整行隐藏
        priceUkr = _numOrNull(m['price_ukr']) ?? 0,
        currencySymbol = '${m['currency_symbol'] ?? '\$'}',
        imageUrl = _strOrNull(m['image_url']),
        imageCount = _intOrNull(m['image_count']) ?? 0,
        minOrderQty = _intOrNull(m['min_order_qty']),
        leadTimeDays = _intOrNull(m['lead_time_days']), // null=卖家没填，不是当天发货
        supportsOnlinePay = _boolOf(m['supports_online_pay']),
        supportUk = _boolOf(m['support_uk']),
        inStock = _boolOf(m['in_stock']),
        rating = _numOrNull(m['rating']), // null=还没有评分，不打成 0 分
        publishedAt = _strOrNull(m['published_at']),
        url = _strOrNull(m['url']),
        isPromoted = m['is_promoted'] == true; // 只有列表层有；广告披露，不能自己推断

  final String slug;
  final String? sellerSlug;
  final String sellerName;
  final String title;
  final String? sku;
  final double priceUkr;
  final String currencySymbol;
  final String? imageUrl;
  final int imageCount;
  final int? minOrderQty;
  final int? leadTimeDays;
  final bool supportsOnlinePay;
  final bool supportUk;
  final bool inStock;
  final double? rating;
  final String? publishedAt;
  final String? url;
  final bool isPromoted;
}

class MarketListedBounds {
  MarketListedBounds.fromMap(Map<String, dynamic> m)
      : gte = '${m['gte'] ?? ''}',
        lt = '${m['lt'] ?? ''}';
  final String gte;
  final String lt;
}

class MarketListedEcho {
  MarketListedEcho.fromMap(Map<String, dynamic>? m)
      : kind = _strOrNull(m?['kind']), // null=这个参数没有生效，不是 1970 年
        day = _strOrNull(m?['day']),
        from = _strOrNull(m?['from']),
        to = _strOrNull(m?['to']),
        days = _intOrNull(m?['days']),
        bounds = m?['bounds'] == null ? null : MarketListedBounds.fromMap(_mapOf(m!['bounds'])),
        notes = (m?['notes'] as List?)?.map((e) => '$e').toList() ?? const [];

  final String? kind;
  final String? day;
  final String? from;
  final String? to;
  final int? days;
  final MarketListedBounds? bounds;
  final List<String> notes;
}

class MarketProductPage {
  MarketProductPage.fromMap(Map<String, dynamic> m)
      : items = _mapList(m['items']).map(MarketCard.fromMap).toList(),
        page = _intOrNull(m['page']) ?? 1, // 必须采纳服务端回显，不能假定「我请求几就是几」（§5.2）
        pageSize = _intOrNull(m['page_size']) ?? 24,
        total = _intOrNull(m['total']) ?? 0,
        totalPages = _intOrNull(m['total_pages']) ?? 1,
        lang = '${m['lang'] ?? 'uk'}',
        sort = '${m['sort'] ?? 'recommended'}', // 生效档位回显，chip 靠它点亮
        listed = MarketListedEcho.fromMap(_mapOf(m['listed']));

  final List<MarketCard> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final String lang;
  final String sort;
  final MarketListedEcho listed;
}

class MarketCatalogNode {
  MarketCatalogNode.fromMap(Map<String, dynamic> m)
      : id = '${m['id'] ?? ''}',
        parentId = _strOrNull(m['parent_id']),
        slug = '${m['slug'] ?? ''}',
        depth = _intOrNull(m['depth']) ?? 0,
        name = '${m['name'] ?? ''}', // 服务端已按语言折好，App 不要再按三列自己挑
        sortOrder = _intOrNull(m['sort_order']) ?? 0,
        listingCount = _intOrNull(m['listing_count']) ?? 0;

  final String id;
  final String? parentId;
  final String slug;
  final int depth;
  final String name;
  final int sortOrder;
  final int listingCount;
}

class MarketCatalog {
  MarketCatalog.fromMap(Map<String, dynamic> m)
      : lang = '${m['lang'] ?? 'uk'}',
        categories = _mapList(m['categories']).map(MarketCatalogNode.fromMap).toList(),
        totalListings = _intOrNull(m['total_listings']) ?? 0;

  final String lang;
  final List<MarketCatalogNode> categories;
  final int totalListings;
}

// ---------- 上架日历 ----------

class MarketListedDayRow {
  MarketListedDayRow.fromMap(Map<String, dynamic> m)
      : date = '${m['date'] ?? ''}',
        count = _intOrNull(m['count']) ?? 0;
  final String date;
  final int count;
}

class MarketListedDayFacet {
  MarketListedDayFacet.fromMap(Map<String, dynamic> m)
      : timezone = '${m['timezone'] ?? ''}',
        today = _strOrNull(m['today']), // 服务端的那一个「今天」（Europe/Kyiv），客户端不自算
        windowDays = _intOrNull(m['window_days']),
        windowFrom = _strOrNull(m['window_from']),
        listedDays = _mapList(m['listed_days']).map(MarketListedDayRow.fromMap).toList(),
        activeDays = _intOrNull(m['active_days']) ?? 0,
        emptyDays = _intOrNull(m['empty_days']) ?? 0,
        scanned = _intOrNull(m['scanned']) ?? 0,
        truncated = m['truncated'] == true, // 为真时这一格是下界，画法要能说「至少 N 条」
        scanCap = _intOrNull(m['scan_cap']) ?? 0,
        unparsed = _intOrNull(m['unparsed']) ?? 0,
        outsideWindow = _intOrNull(m['outside_window']) ?? 0,
        lang = '${m['lang'] ?? 'uk'}',
        window = m['window'] == null ? null : MarketWindow.fromMap(_mapOf(m['window'])),
        selected = MarketListedEcho.fromMap(_mapOf(m['selected'])),
        reason = _strOrNull(m['reason']); // category_not_found / window_unavailable ⇒ 日历整块不渲染

  final String timezone;
  final String? today;
  final int? windowDays;
  final String? windowFrom;
  final List<MarketListedDayRow> listedDays;
  final int activeDays;
  final int emptyDays;
  final int scanned;
  final bool truncated;
  final int scanCap;
  final int unparsed;
  final int outsideWindow;
  final String lang;
  final MarketWindow? window;
  final MarketListedEcho selected;
  final String? reason;

  bool get renderable => window != null && reason == null;
}

class MarketWindow {
  MarketWindow.fromMap(Map<String, dynamic> m)
      : from = '${m['from'] ?? ''}',
        to = '${m['to'] ?? ''}',
        days = _intOrNull(m['days']) ?? 30;
  final String from;
  final String to;
  final int days;
}

// ---------- 详情 ----------

class MarketSellerBlock {
  MarketSellerBlock.fromMap(Map<String, dynamic> m)
      : slug = '${m['slug'] ?? ''}',
        name = '${m['name'] ?? ''}',
        supportUk = _boolOf(m['support_uk']),
        onlinePay = _boolOf(m['online_pay']),
        listingCount = _intOrNull(m['listing_count']); // null=这一格没读到，画 —，不画 0

  final String slug;
  final String name;
  final bool supportUk;
  final bool onlinePay;
  final int? listingCount;
}

class MarketCategoryRef {
  MarketCategoryRef.fromMap(Map<String, dynamic> m)
      : slug = '${m['slug'] ?? ''}',
        nameUk = '${m['name_uk'] ?? ''}',
        nameEn = '${m['name_en'] ?? ''}';
  final String slug;
  final String nameUk;
  final String nameEn;
}

class MarketProductDetail {
  MarketProductDetail.fromMap(Map<String, dynamic> m)
      : card = MarketCard.fromMap(m),
        description = _strOrNull(m['description']),
        descriptionEn = _strOrNull(m['description_en']),
        imageUrls = (m['image_urls'] as List?)?.map((e) => '$e').toList() ?? const [],
        specAttrs = _mapOf(m['spec_attrs']),
        ttfrHours = _numOrNull(m['ttfr_hours']), // null=还没有可测的留资响应 → 整行消失
        chatEnabled = _boolOf(m['chat_enabled']),
        buyerGateEnabled = _boolOf(m['buyer_gate_enabled']),
        seller = MarketSellerBlock.fromMap(_mapOf(m['seller'])),
        category = m['category'] == null ? null : MarketCategoryRef.fromMap(_mapOf(m['category'])),
        related = _mapList(m['related']).map(MarketCard.fromMap).toList();

  final MarketCard card;
  final String? description;
  final String? descriptionEn;
  final List<String> imageUrls;
  final Map<String, dynamic> specAttrs;
  final double? ttfrHours;
  final bool chatEnabled;
  final bool buyerGateEnabled;
  final MarketSellerBlock seller;
  final MarketCategoryRef? category;
  final List<MarketCard> related;
}

class MarketSellerPage {
  MarketSellerPage.fromMap(Map<String, dynamic> m)
      : sellerSlug = '${_mapOf(m['seller'])['slug'] ?? ''}',
        sellerName = '${_mapOf(m['seller'])['name'] ?? ''}',
        // 店铺页 items 是纯卡片，没有 is_promoted——那一格不是平台卖出去的格子，标了就是虚假披露
        items = _mapList(m['items']).map(MarketCard.fromMap).toList(),
        page = _intOrNull(m['page']) ?? 1,
        pageSize = _intOrNull(m['page_size']) ?? 24,
        total = _intOrNull(m['total']) ?? 0;

  final String sellerSlug;
  final String sellerName;
  final List<MarketCard> items;
  final int page;
  final int pageSize;
  final int total;
}

// ---------- 留资 ----------

class MarketLeadResult {
  MarketLeadResult.fromMap(Map<String, dynamic> m)
      : leadId = '${m['lead_id'] ?? ''}',
        orderNumber = _strOrNull(m['order_number']), // 唯一可能为 null：只说明号还没落到，不是失败 → 整行隐藏
        sellerName = '${m['seller_name'] ?? ''}',
        quotedAmount = _numOrNull(m['quoted_amount']) ?? 0, // 服务端按投影价重算，App 不算钱
        currency = '${m['currency_symbol'] ?? m['currency'] ?? ''}',
        quantity = _intOrNull(m['quantity']),
        contactMasked = '${m['contact_masked'] ?? ''}', // maskPhone() 的产物，不是买家刚输入的原文
        nextStep = '${m['next_step'] ?? ''}';

  final String leadId;
  final String? orderNumber;
  final String sellerName;
  final double quotedAmount;
  final String currency;
  final int? quantity;
  final String contactMasked;
  final String nextStep;
}

// ---------- 客服 ----------

class MarketChatMessage {
  MarketChatMessage.fromMap(Map<String, dynamic> m)
      : id = _intOrNull(m['id']) ?? 0,
        sender = '${m['sender'] ?? 'buyer'}', // buyer | seller | system
        body = '${m['body'] ?? ''}',
        createdAt = '${m['created_at'] ?? ''}';
  final int id;
  final String sender;
  final String body;
  final String createdAt;

  Map<String, dynamic> toMap() => {'id': id, 'sender': sender, 'body': body, 'created_at': createdAt};
}

class MarketChatState {
  MarketChatState.fromMap(Map<String, dynamic> m)
      : conversationToken = _strOrNull(m['conversation_token']),
        status = '${m['status'] ?? 'open'}', // open | closed | blocked
        sellerName = '${m['seller_name'] ?? ''}',
        listingTitle = '${m['listing_title'] ?? ''}',
        messages = _mapList(m['messages']).map(MarketChatMessage.fromMap).toList(),
        serverTime = _strOrNull(m['server_time']);

  final String? conversationToken;
  final String status;
  final String sellerName;
  final String listingTitle;
  final List<MarketChatMessage> messages;
  final String? serverTime;
}

class MarketChatAppendResult {
  MarketChatAppendResult.fromMap(Map<String, dynamic> m)
      : status = '${m['status'] ?? 'open'}',
        appended = m['appended'] == null ? null : MarketChatMessage.fromMap(_mapOf(m['appended']));
  final String status;
  final MarketChatMessage? appended;
}

// ---------- 买家账号 ----------

class BuyerAccount {
  BuyerAccount.fromMap(Map<String, dynamic> m)
      : name = _strOrNull(m['name']), // 墓碑后为 null——按 status 出本地化文案，不打印库里的 'deleted'
        phoneMasked = '${m['phone_masked'] ?? ''}',
        lang = '${m['lang'] ?? ''}',
        country = _strOrNull(m['country']),
        consentMarketing = _boolOf(m['consent_marketing']),
        createdAt = '${m['created_at'] ?? ''}',
        lastLoginAt = _strOrNull(m['last_login_at']);

  final String? name;
  final String phoneMasked;
  final String lang;
  final String? country;
  final bool consentMarketing;
  final String createdAt;
  final String? lastLoginAt;
}

class BuyerAuthResult extends BuyerAccount {
  // ignore: use_super_parameters
  BuyerAuthResult.fromMap(Map<String, dynamic> m)
      : sessionToken = '${m['session_token'] ?? ''}',
        sessionExpiresAt = '${m['expires_at'] ?? ''}',
        super.fromMap(m);
  final String sessionToken; // 唯一一次出现，此后任何接口都不再回它
  final String sessionExpiresAt;
}

class BuyerStats {
  BuyerStats.fromMap(Map<String, dynamic> m)
      : conversations = _intOrNull(m['conversations']), // number|null：null 是「没读到」，画短横+未取到
        favorites = _intOrNull(m['favorites']),
        leads = _intOrNull(m['leads']);
  final int? conversations;
  final int? favorites;
  final int? leads;
}

class BuyerMe extends BuyerAccount {
  // ignore: use_super_parameters
  BuyerMe.fromMap(Map<String, dynamic> m)
      : stats = BuyerStats.fromMap(_mapOf(m['stats'])),
        sessionExpiresAt = '${_mapOf(m['session'])['expires_at'] ?? ''}',
        super.fromMap(m);
  final BuyerStats stats;
  final String sessionExpiresAt;
}

// ---------- 个人页三块 ----------

class BuyerPage<T> {
  BuyerPage.fromMap(Map<String, dynamic> m, T Function(Map<String, dynamic>) rowFrom)
      : lang = _strOrNull(m['lang']),
        items = _mapList(m['items']).map(rowFrom).toList(),
        page = _intOrNull(m['page']) ?? 1,
        pageSize = _intOrNull(m['page_size']) ?? 24,
        total = _intOrNull(m['total']) ?? 0; // total 是自己这一块的，不是全站的
  final String? lang;
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
}

class BuyerLeadRow {
  BuyerLeadRow.fromMap(Map<String, dynamic> m)
      : leadId = '${m['lead_id'] ?? ''}',
        status = '${m['status'] ?? ''}', // 词表外的值（如 expired）必须走默认分支说事实，不给改状态入口
        orderNumber = _strOrNull(m['order_number']),
        quotedAmount = _numOrNull(m['quoted_amount']) ?? 0,
        currency = '${m['currency'] ?? ''}', // 历史行可能带 'UAH' 标签：拿到什么印什么，不统一
        quantity = _intOrNull(m['quantity']),
        sellerName = '${m['seller_name'] ?? ''}',
        sellerSlug = _strOrNull(m['seller_slug']),
        slug = _strOrNull(m['slug']),
        listingTitle = '${m['listing_title'] ?? ''}',
        listingVisible = m['listing_visible'] == true,
        createdAt = '${m['created_at'] ?? ''}',
        respondedAt = _strOrNull(m['responded_at']);

  final String leadId;
  final String status;
  final String? orderNumber;
  final double quotedAmount;
  final String currency;
  final int? quantity;
  final String sellerName;
  final String? sellerSlug;
  final String? slug;
  final String listingTitle;
  final bool listingVisible;
  final String createdAt;
  final String? respondedAt;
}

class BuyerConversationRow {
  BuyerConversationRow.fromMap(Map<String, dynamic> m)
      : conversationToken = '${m['conversation_token'] ?? ''}',
        lang = '${m['lang'] ?? ''}',
        status = '${m['status'] ?? 'open'}',
        sellerName = '${m['seller_name'] ?? ''}',
        sellerSlug = _strOrNull(m['seller_slug']),
        slug = _strOrNull(m['slug']),
        listingTitle = '${m['listing_title'] ?? ''}',
        createdAt = '${m['created_at'] ?? ''}',
        lastBuyerAt = _strOrNull(m['last_buyer_at']),
        lastSellerAt = _strOrNull(m['last_seller_at']),
        lastMessage = m['last_message'] == null ? null : BuyerLastMessage.fromMap(_mapOf(m['last_message']));

  final String conversationToken;
  final String lang;
  final String status;
  final String sellerName;
  final String? sellerSlug;
  final String? slug;
  final String listingTitle;
  final String createdAt;
  final String? lastBuyerAt;
  final String? lastSellerAt;
  final BuyerLastMessage? lastMessage;
}

class BuyerLastMessage {
  BuyerLastMessage.fromMap(Map<String, dynamic> m)
      : sender = '${m['sender'] ?? ''}',
        body = '${m['body'] ?? ''}',
        createdAt = '${m['created_at'] ?? ''}';
  final String sender;
  final String body;
  final String createdAt;
}

class BuyerFavoriteRow {
  BuyerFavoriteRow.fromMap(Map<String, dynamic> m)
      : card = MarketCard.fromMap(m),
        addedAt = '${m['added_at'] ?? ''}',
        listingVisible = m['listing_visible'] == true; // false ⇒ 渲染这一行但不给链接
  final MarketCard card;
  final String addedAt;
  final bool listingVisible;
}

class FavoriteAddResult {
  FavoriteAddResult.fromMap(Map<String, dynamic> m)
      : slug = '${m['slug'] ?? ''}',
        favorited = m['favorited'] == true,
        already = m['already'] == true;
  final String slug;
  final bool favorited;
  final bool already;
}

class FavoriteRemoveResult {
  FavoriteRemoveResult.fromMap(Map<String, dynamic> m)
      : slug = '${m['slug'] ?? ''}',
        removed = m['removed'] == true; // 本来就不在 ⇒ removed:false 且 HTTP 200：直接改成未收藏，不是报错
  final String slug;
  final bool removed;
}

class FavoriteMigrateResult {
  FavoriteMigrateResult.fromMap(Map<String, dynamic> m)
      : migrated = _intOrNull(m['migrated']) ?? 0,
        skipped = _intOrNull(m['skipped']) ?? 0,
        truncated = m['truncated'] == true,
        total = _intOrNull(m['total']);
  final int migrated;
  final int skipped;
  final bool truncated;
  final int? total;
}

// ---------- 展示工具 ----------

/// App 唯一被授权的算术是显示：千分位与符号前缀（§7.3）。除此之外不要有第二处把价格和数量相乘的代码。
String formatPrice(double value, String symbol) {
  final s = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final buf = StringBuffer();
  final digits = parts.first.replaceAll('-', '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = s.startsWith('-') ? '-' : '';
  final tail = parts.length > 1 ? '.${parts[1]}' : '';
  return '$sign$symbol$buf$tail';
}
