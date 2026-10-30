# 公域端 App 开发文档

> 版本：v1.1 · 2026-10-30（v1.0 同日成稿；v1.1 的差异见 §11.3 修订记录）
> 状态：施工图（本文档描述**现有服务端契约**，供重开发公域端买家 App 使用）
> 范围：公域集市（`/market*`，下文统称「公域端」）——**不含**租户控制台 `/app/*`、超管后台 `/admin*`、公开展厅 `/s/:token`
> 读者：负责重写公域端买家 App 的开发者（原生 / Flutter / 混合壳皆可）
> 姊妹文档：`docs/inventory-app-development.md`（库存端 App 开发文档）。两份文档**共用第 3 章的信封、超时、限流口径**，但身份体系完全不同，不要交叉复用凭证与存储键。

## 目录

- [1. 文档定位与适用范围](#1-文档定位与适用范围)
- [2. 结论先行：三条技术路线与推荐](#2-结论先行三条技术路线与推荐)
- [3. 服务端契约总览](#3-服务端契约总览)
- [4. 身份与鉴权](#4-身份与鉴权)
- [5. 通用约定](#5-通用约定)
- [6. 模块规格](#6-模块规格)
- [7. 关键业务不变量](#7-关键业务不变量)
- [8. 移动端专属要求](#8-移动端专属要求)
- [9. 发布与合规](#9-发布与合规)
- [10. 验收清单](#10-验收清单)
- [11. 未验证事项与已知缺陷](#11-未验证事项与已知缺陷)
- [12. 附录](#12-附录)
- [结语](#结语)

---

## 1. 文档定位与适用范围

### 1.1 本文档是什么

这是一份**公域买家 App 的重开发施工图**，不是接口草稿，也不是设计稿。它回答三个问题：

1. **客户端能调什么**——`/api/market/*` 的 26 条公开路由、每条的方法、限流桶、必填参数、超时建议（见 §12.1）。
2. **客户端必须怎么理解返回值**——哪些 `null` 不能打印成 `0`、哪些字段是服务端裁定而不是数据、哪些标签是广告披露而不能自己推断（见 §7）。
3. **哪些事情结构上做不到**——买家 App 不直接碰数据库、不上传图片、不做手机搜索、不自建账号体系（见 §2.2、§8.3）。

三条关键事实，全文的所有规则都从这里长出来：

- **公域端是一个被买来的流量落地页，不是库存系统的一个模块。** `/market` 的目的是让乌克兰 B2B 买家在付费点击上看到供给、留资、开店、发消息。一次「刷新一下界面」的工程决策，代价是付费点击转化率，不是开发体验。
- **买家与租户是两套身份，永不在同一个浏览器里互换。** 库存端 App 用 Supabase Auth；公域买家账号是服务端会话行 + `X-Buyer-Session` 头。两者不能共用存储键、不能共用刷新逻辑、不能互相读取。
- **公域页面能看到的，只有 `mp_listing_public` 这一张投影表。** 这是平台唯一的跨域通道。任何"顺手读一下 products / inventory / orders"的接口在公域 API 里不存在，也不应该存在。

本文档**不描述 UI 像素**。配色、圆角、字号、吸底条高度在第 8 章按「必须读哪个 token / 哪个 CSS 变量」的方式给出，具体数值请看 `src/pages/market/**` 与 `src/styles/globals.css` 的 `[data-surface='market']` 块。

### 1.2 本文档不与什么相关

| 面 | 地址 | 身份 | 是否在本文档范围 |
| --- | --- | --- | --- |
| 公域集市 | `/market`、`/market/p/:slug`、`/market/s/:seller`、`/market/me` | 公域买家账号（可匿名浏览） | ✅ 本文档全部内容 |
| 租户控制台 | `/app/*`（9 个模块） | Supabase Auth + `Authorization: Bearer` | ❌ 见 `docs/inventory-app-development.md` |
| 超管后台 | `/admin`、`/admin/t/:tenantId/:view`、`/admin/market-ops` | 平台人员（`super_admin` / `platform_staff`） | ❌ |
| 公开展厅 | `/s/:token` | 无鉴权，走 `/api/showroom/*` | ❌ 是另一条服务端链，与集市投影无关 |
| 官网与文档中心 | `/home`、`/docs`、`/docs/:slug` | 无鉴权，纯静态内容（`src/content/**`） | ❌ |
| 卖家侧集市 | `/app/marketplace`（选品 / 公域表现 / 客服 / 投放） | 租户身份，走 `/api/business/marketplace/*` | ❌ 卖家不是买家 |

最后一行需要特别说明：**客服会话的两端在两套 API 里。** 买家侧的 `POST /api/market/chat`、`GET /api/market/chat/:token` 属于本文档；卖家侧的收件箱、Telegram 绑定、邀请留资全部在租户控制台，属于库存端文档。本文档只给出买家一侧的契约。

### 1.3 现有交付物（重开发时可对照，也可保留）

| 交付物 | 位置 | 作用 | 重开发时的处置 |
| --- | --- | --- | --- |
| 公域集市 PWA | `public/market-manifest.json`，名称 `torgseek`，`scope: /market` | 买家「添加到主屏幕」的独立 App 身份 | **保留**。它与库存端 PWA（`torgseek 库存`，`scope: /`）是两个磁贴，故意不同名 |
| Service Worker | `public/sw.js`，`CACHE_VERSION = v7` | 预缓存壳与两套图标；**从不缓存 `/api/*`** | 保留。改了被预缓存的资源必须升 `CACHE_VERSION` |
| 头部元数据替换 | `src/pages/market/seo.ts`（`applyMarketSeo` + `swapMarketIcons`） | 把 manifest / theme-color / 整组 favicon / apple 标题换成集市身份 | 保留 |
| 构建期预渲染 | `scripts/prerender-market.mjs` | 出 `dist/market/index.html`、`p/<slug>`、`s/<slug>`、`sitemap.xml`——**只改 `<head>`** | 保留。**不预渲染 `<body>`**，见 §9 说明 |
| 安装提示 | `src/pages/market/pwa.ts`（`beforeinstallprompt` 单例 + `useMarketInstall()`） | 首页 hero 旁的安装按钮；iOS 给手动提示而不是假按钮 | 保留 |
| TWA 安装包 | `public/downloads/torgseek-market.apk` | 公域集市的 Android 外壳，运行时打开 `www.torgseek.com/market` | **保留**，但注意：包内没有业务代码，运行主机是 Chrome，iOS / HarmonyOS NEXT 用不了 |
| 数字资产关联 | `public/.well-known/assetlinks.json` | TWA 的可信启动凭据 | **load-bearing**，见 §9.4 |
| 买家会话客户端 | `src/api/buyerAuth.ts` | 唯一持有 `yuanbao.market.buyer.session` 与 `buyerHeaders()` | **照抄这份契约**（§4、§12.4） |
| 集市 API 客户端 | `src/api/market.ts` | 全部 `/api/market/*` 调用 + 出参类型 + 超时 | **照抄这份契约**（§12.1、§12.4） |
| 埋点通道 | `src/pages/market/analytics.ts` | `/market*` 下**唯一**的埋点出口 | 见 §6.9——App 若替换整个前端，必须保留同一个事件词表 |

> 一句话：**TWA 不是"另一个版本的产品"**。它里面没有一行库存或集市业务代码，所有像素与数据都来自线上站点，所以站点改了，重开 App 就是新版本，**没有升级包这回事**。

---

## 2. 结论先行：三条技术路线与推荐

### 2.1 路线对比

| 维度 | A. 调 `/api/market/*`（原生 / Flutter / React Native） | B. 直连 Supabase（anon key + PostgREST） | C. WebView 套壳（现有 `/market` 装进壳） |
| --- | --- | --- | --- |
| 后端改动 | **零** | 需要重开整套 RLS 策略 | 零 |
| 功能完整度 | 完整（浏览 / 搜索 / 留资 / 客服 / 账号 / 收藏 / 个人页） | **结构性缺失**，见 §2.2 | 完整（就是现网页） |
| 鉴权 | `X-Buyer-Session`（服务端会话行） | 需要把 scrypt 口令校验搬到客户端，等于没有口令体系 | 浏览器同源会话，无需改动 |
| 买家上传文件 | 不适用（买家不上传，见 §8.3） | 需要为 anon 开 Storage 写策略 | 不适用 |
| 密钥安全 | 只暴露公开值 | 会暴露 `anon key` + 依赖 RLS 是唯一防线 | 只暴露公开值 |
| 多租户隔离 | 由服务端投影表保证 | 由 RLS 策略保证（而公域表**本来就是 0 策略 + REVOKE**） | 由服务端投影表保证 |
| iOS 上架 | 正常 | 正常 | **风险点**：Apple 4.2「最低功能」对纯网页壳判定严格 |
| 工程量 | 中（26 条路由 + 一套身份 + 埋点/归因） | 大（重做安全层） | 小 |
| 稳定性承诺 | 现网每天在跑的同一条链 | 不存在 | 现网 |

### 2.2 B 路线（直连 Supabase）结构上做不到的事

这一节不是"麻烦"清单，是"做不到"清单。每一条都是可验证的事实：

1. **公域表对浏览器角色是 `REVOKE ALL`。** `mp_listing_public` / `mp_buyers` / `mp_attributions` / `mp_conversations` / `mp_messages` / `mp_tenant_channels` / `mp_events` 全部在增表时就自带 `REVOKE ALL FROM anon, authenticated`，并且开了 RLS、0 条策略。anon key 直连的结果是 `42501 permission denied`，不是"读到一点"。
2. **留资不是插入一行。** `createLead()`（`server/marketplace-core/services/public.js:558`）要重查私有 `mp_listings` / `products` / `tenants` / `customers`，走 `process_order_v2` RPC 生成"备货前"订单，再补 `markOrderInPickingList()`，最后写 `mp_leads`。客户端**不可能**在浏览器角色权限下完成这一串。
3. **金额必须服务端重算。** 报价 `quoted_amount` 取的是投影表价的乘积，客户端传来的金额一律被忽略。直连等于把定价权交给抓包的人。
4. **口令体系在服务端。** 密码是自描述 scrypt 串（`scrypt$N$r$p$salt$hash`），校验、软锁（5 次 / 15 分钟）、墓碑（`closeBuyerAccount()`）都在 `buyer-auth.js`。客户端算不出也不该算。
5. **硬登录门在服务端。** 买家发消息的判定只有一个入口 `resolveBuyerIdentity()`（`chat.js:231`），它跑在 slug 解析和 `INSERT` **之前**，所以被拒的匿名尝试**不留任何行**。直连的客户端无法复现这个"不产生脏数据"的性质。
6. **PII 出参是设计出来的。** 手机号出参只有 `maskPhone()`（`util.js:744`）一种形状，`phone_hash` / `password_hash` / `session_token` 连 SELECT 列表都不在。**直连意味着这些列第一次出现在网络上。**
7. **限流与归因在服务端。** `market:*` 桶、IP 哈希、utm 规范化都在 `api/market.js` 与服务层；直连会绕过它们，而付费投放的读数从此不可解释。

**结论：B 路线不是"更简单但安全性差一点"，而是"要做完就得把服务端重写一遍"。**

### 2.3 推荐

- **走 A 路线**：Flutter（或你熟悉的任何原生栈）调用 `https://www.torgseek.com/api/market/*`。所有业务规则、金额、可见性、身份判定都在服务端，客户端只做呈现与分支。
- **构建走云端 GitHub Actions**，不要在本地装 Android / iOS 工具链。库存端 App 已经用同一形状跑通：`.github/workflows/build-apk.yml` 与 `build-ios.yml`，`setup-java` + `flutter build apk` + artifact 上传；公域端复用同一份 workflow 模板，只换产物名与包名。详见 §9.6。
- **C 路线只在"本周就要有个 APK 能装"时用**：现成的 `public/downloads/torgseek-market.apk` 就是这条路已经走完的样子。它不需要新代码，但也不要把它当成 A 路线的成果。
- **绝对不要**把 `yb_live_…` / `yb_admin_…` 外部 API 密钥、`service_role` 密钥、`anon key` 打进分发包。公域端**一个密钥都不需要**：它的全部凭证就是买家自己登录后拿到的 `X-Buyer-Session`。
- **绝对不要**给买家 App 加第二个数据面（例如 Firestore / 本地镜像库 / 直连 Postgres）。这一条在库存端那轮讨论里被单独拿出来推迟，在公域端**是直接禁止**：投影表就是公域唯一的数据真相来源，多一个数据面就是多一处会对不上的读数（§7.1、§7.3）。

---

## 3. 服务端契约总览

### 3.1 三类 API 面

| API 面 | 入口文件 | 调用方 | 鉴权头 | 本文档 |
| --- | --- | --- | --- | --- |
| `/api/market/*` | `api/market.js`（catch-all，26 条路由） | 公域买家（可匿名） | 无 / `X-Buyer-Session` | ✅ |
| `/api/business/*` | `api/business.js` | 租户控制台 | `Authorization: Bearer <supabase token>` | ❌ |
| `/api/showroom/*` | `api/showroom.js` | 公开展厅访客 | 无（token 在路径里） | ❌ |

`/api/market/*` 的路由集中在一个文件里，路由匹配是**手写的 `if (method === ... && resource === ...)` 链**，不是 Express 路由器。你要加端点就是在 `api/market.js` 里插一个 `if` 块；你要调端点就是照 §12.1 的表。

`normalizePath()`（`api/market.js:41–48`）把 `req.query.path` 拼成资源段，所以 `/api/market/products/abc` 对服务端是 `['products','abc']`。这对客户端的含义：**路径参数一律走真实路径**，不要把参数塞进查询串冒充路径。

### 3.2 响应信封

所有接口（含错误）都返回同一信封（`server/admin-core/response.js`）：

```jsonc
// 成功
{ "ok": true, "data": { /* 业务负载 */ },
  "meta": { "requestId": "...", "generatedAt": "2026-10-30T..." } }

// 失败
{ "ok": false, "error": { "code": "BUYER_SESSION_EXPIRED", "message": "...", "details": { /* 可选 */ } },
  "meta": { "requestId": "...", "generatedAt": "..." } }
```

铁律：

- **客户端只按 `error.code` 分支**（§12.2 是完整词表）。`message` 是给人看的中文文案，会变，不要解析它，更不要拿它当枚举值。
- `details` 是**可选**的，且只有部分错误码带它（例如 `BELOW_MIN_ORDER` 带 `details.min_order_qty`，`OVER_STOCK` 带 `details.stock`）。带不带、带什么，看 §6 各模块。
- 集市 handler 的错误兜底在 `api/market.js:372–383`：**只有服务端显式标了 `exposeMessage` 的 5xx 才把原文给你**，其余一律塌成「集市 API 内部错误」。也就是说，`500` 系列里只有一句是可直接展示的（见 §6.6 的 `process_order_v2` 库存不足文案），其余请展示通用失败 + `requestId`。

### 3.3 反向代理与超时

- Vercel 函数 `maxDuration: 30` 秒（`vercel.json`）。服务端自己也在 30 秒预算内写代码，所以**任何一次调用都可能因为上游抖动而超时**，尤其是留资（它要跑 RPC + 四次读）。
- 先说清一件事，因为它会决定你怎么读 §12.1 的超时列：**浏览器侧并没有「逐条调过」的超时。** `src/api/client.ts:71` 的 `apiCall()` 默认值是 `timeout = 30_000`，而**五条公域读根本没有传 `timeout`**——`getMarketCatalog`、`listMarketProducts`、`getMarketListedDays`、`getMarketProduct`、`listMarketSellerProducts`（`src/api/market.ts:212–270`，其中详情那一条写成三行 options 对象，所以「只看一行」的检索会漏掉它）。它们跑的是缺省 30 s，不是某个被权衡过的数字。**被逐条调过的只有 7 + 13 = 20 条**：`src/api/market.ts` 里的写路径、跟踪配置、埋点与客服，加上 `src/api/buyerAuth.ts` 的全十三条。
- 所以下面这组值是**全文唯一的超时数字之家**，§12.1 端点总表的最后一列逐字照抄它，§12.3 只谈可重试性与退避而不重复数字。它分成两种形状，请在表里也保持这两种形状可区分——**「显式值」与「未设显式超时 ⇒ 走 `apiCall` 默认 30 s（`src/api/client.ts:71）」是两句不同的话**，把后者写成前者等于给一个没做过的决定背书：
  - 公域读（目录 / 列表 / 日历 / 详情 / 店铺列表）：**未设显式超时 ⇒ 默认 30 s**。`getTrackingConfig` 与 `trackMarketView` 是这一组里唯二被显式调过的，都是 **10 s**——它们**不该**拖慢首屏，所以宁可短。
  - 留资：**45 s**（`submitMarketLead`，全文件最长，因为它串了 RPC）。
  - 账号写：注册 / 登录 / 改密 / 注销 **20 s**；`me` / 登出 **15 s**（`src/api/buyerAuth.ts:109/118/150/163` 与 `:123/132`）。
  - 个人页读：`listBuyerLeads` / `listBuyerConversations` / `listBuyerFavorites` / `listBuyerFavoriteSlugs` **15 s**；收藏写：**加与移除是 15 s（`:267` / `:277`），只有迁移 20 s（`:305`）**。
  - 客服：起会话 / 发消息 **20 s**（`:419` / `:440`），轮询 **15 s**（`:427`）。
  - 埋点批：**8 s**（`postMarketEvents`，且带 `keepalive`，见 §6.9——`keepalive` 会把超时上限再压到 8 s，见 `src/api/client.ts:75`）。
- 冷启动是真实存在的：`GET /api/market/warmup`（`api/market.js:165–173`）是无鉴权探针，GitHub Action 每 5 分钟打一次。**冷启动那一两秒请用骨架屏呈现，不要转成失败重试。**

### 3.4 双域名与跨域（App 的关键差异）

2026-10-20 起生产是**一次部署、两个主机**：

| 主机 | 服务 | 库存端 App 指向 | 公域端 App 指向 |
| --- | --- | --- | --- |
| `app.torgseek.com` | `/app/*` 控制台 + `/admin*` 后台 | ✅ | ❌ |
| `www.torgseek.com` | `/home`、`/docs*`、`/market*`、`/s/:token` | ❌ | ✅ |

两个主机共用同一套 `/api/*`，浏览器里各自同源调用，因此**不需要跨域白名单**。但 App 不一样：

- **`api/market.js` 的 CORS 只有 `GET, POST, OPTIONS`**（`setCorsHeaders`，`api/market.js:69–87`）。没有 `PUT` / `PATCH` / `DELETE`。这直接解释了为什么"取消收藏"是一条 `POST /buyer/favorites/remove` 而不是 `DELETE`（`src/api/buyerAuth.ts:258–260` 把这条写成注释钉住了）。
- **`APP_CORS_ORIGINS` 是 App / WebView 唯一的跨域出口**，同一处代码写明「给 App WebView / 落地页用；缺省保持仅同源」。也就是说：
  - 一个**原生 HTTP 客户端**（iOS URLSession、OkHttp、Dart `http`）**不受 CORS 约束**——CSP 和 CORS 只约束浏览器。A 路线默认就是这个形状。
  - 一个 **WebView** 想在壳里直接 fetch 站点 API，需要服务端配 `APP_CORS_ORIGINS`，且只用 GET/POST。**本文档不假设这种形状**；如果要走 WebView，请把它当成一次独立的配置变更。
- **旧域名 `7-km.com` 已彻底下线。** 它的 308 现在只活在一个 Cloudflare 边缘重定向规则里，仓库里没有任何东西能恢复它。**不要在 App 里硬编码旧域名**，也不要假设旧链接会被 App 接管。

> 建议把 Base URL 做成可配置项（`apiBase = https://www.torgseek.com/api/market`），而不是把域名字面量散落在每一个调用点。库存端 App 的对应文件是 `lib/core/env.dart`。

### 3.5 限流

`server/business-core/rate-limit.js` 的实现是**进程内 `Map`**：冷启动清零、多实例不共享、按 IP 或按凭证分桶。因此：

- **不要把限流当配额或业务规则使用**，它只是防刷。真实配额在业务层（例如收藏上限 `BUYER_FAVORITES_MAX = 200`，`buyer-auth.js:562`）。
- 遇到 `429 RATE_LIMITED` 应**指数退避**（1s / 2s / 4s），并且只对幂等的 GET 自动重试（§5.1）。
- **明文手机号不进限流键**：`phoneKey()`（`api/market.js:130–134`）先做哈希再进 Map。
- **限流键的最后一律是 IP，一个例外都没有。** `checkRateLimit()` 在 `rate-limit.js:21` 无条件拼出 `${scope}:${clientIp(req)}`，所以表里写的 `scope` 只是**键的前半段**。对 App 的真实含义有两个方向：
  - 凭证类桶（`buyer-me` / `buyer-close` / 个人页那七条）在换 IP 时会**换桶**，等于计数归零——移动网络下这一条对你有利。
  - 反过来，「同凭证跨 IP 不被别人挡」成立，但「跨 IP 反复试同一个号码」这一半**内存桶永远管不住**，所以它由 `mp_buyer_accounts` 的持久软锁接管（§4.5），不是由这张表接管。
- **`X-RateLimit-Remaining` 每个响应都带，`Retry-After` 只在 429 时带**（`applyRateLimit()`，`rate-limit.js:38–45`）。这两个头是现成的：App 的节流与「稍后再试」文案应该读它们，而不是自己数请求。

`/api/market/*` 的桶（**逐条抄自 `api/market.js` 的 `applyRateLimit` 调用点**，scope 字面量、阈值、行号都是代码里的原值）：

| 路由 | scope 字面量（仍会再拼 `:${ip}`） | 阈值 | 行号 |
| --- | --- | --- | --- |
| `GET warmup` | `market:warmup` | 30 / min | `:166` |
| `GET catalog` | `market:catalog` | 240 / min | `:176` |
| `GET tracking-config` | `market:tracking-config` | 240 / min | `:184` |
| `GET products` | `market:products` | 240 / min | `:190` |
| `GET listed-days` | `market:listed-days` | 240 / min | `:199` |
| `GET products/:slug` | `market:detail` | 240 / min | `:205` |
| `GET sellers/:slug` | `market:seller` | 240 / min | `:211` |
| `POST leads` ① | ``market:leads:${ip}`` | 8 / min | `:218` |
| `POST leads` ② | ``market:leads:${slug}``（缺 slug → `na`） | 30 / min | `:220` |
| `POST chat` ① | ``market:chat:${ip}`` | 8 / min | `:230` |
| `POST chat` ② | ``market:chat:${slug}``（缺 slug → `na`） | 30 / min | `:232` |
| `GET chat/:token` | ``market:chat:${token}`` | 60 / min | `:238` |
| `POST chat/:token/messages` ① | ``market:chat:${ip}`` | 8 / min | `:245` |
| `POST chat/:token/messages` ② | ``market:chat:send:${token}`` | 20 / min | `:247` |
| `POST buyer/register` ① | `market:buyer-register` | 20 / min | `:258` |
| `POST buyer/register` ② | ``market:buyer-register-phone:${phoneKey}`` | **5 / 10 min** | `:260` |
| `POST buyer/login` ① | `market:buyer-login` | 10 / min | `:267` |
| `POST buyer/login` ② | ``market:buyer-login-phone:${phoneKey}`` | **5 / 15 min** | `:269` |
| `GET buyer/me` | ``market:buyer-me:${token|'anon'}`` | 60 / min | `:275` |
| `POST buyer/logout` | ``market:buyer-logout:${token|'anon'}`` | 30 / min | `:281` |
| `POST buyer/password` | ``market:buyer-change:${token|'anon'}`` | 10 / min | `:287` |
| `POST buyer/close` | ``market:buyer-close:${token|'anon'}`` | 5 / min | `:295` |
| 个人页 7 条 | ``market:buyer-${action}:${token|'anon'}`` | 60 / min | `:142` |
| `POST track` | ``market:track:${ip}`` | 600 / min | `:352` |
| `POST events` | ``market:events:${ip}`` | 120 / min | `:363` |

四处这张表替你挡掉的坑：

- **`POST buyer/password` 的桶叫 `buyer-change`，不叫 `buyer-password`。** 路由段是 `password`，scope 是 `change`——照着路由名猜 scope 的人会以为这一条没限流。
- **个人页七条路由只用五个 action**。`GET favorites` 与 `GET favorites/slugs` 共用 `favorites`，加收藏与删收藏共用 `favorite-write`，所以「连点十颗心」和「刷十次 slugs」撞的是同一个桶。迁移单独一个 `favorite-migrate`（整批一次写，`:345`）。这五个名字是 `:305`–`:345` 传进来的字符串，App 侧不需要知道，但**压测时要按五个桶算**，不是按七条路由算。
- **写操作的号码桶单位不是分钟**：注册 5 / **10 分钟**、登录 5 / **15 分钟**。按 5/min 实现退避的客户端会以为自己还能再试四次，实际上服务端已经把它挡在窗口外。
- **`POST leads` 与 `POST chat` 的两支桶共用一个前缀**（`market:leads:` / `market:chat:`），只是第二段不同。这不是笔误：IP 桶挡「一个 IP 扫一批商品」，slug 桶挡「一个商品被刷」，两桶任一命中都是 429，而**文案不同**（「提交过于频繁」vs「该商品提交过于频繁」，`api/market.js:219` / `:221`）。App 展示哪一句都行，分支只看 `code`。

顺带一句代码读感：`:218`、`:230` 这类 scope 里已经写了 `${ip}`，而 `rate-limit.js:21` 会再拼一次 IP，所以现网真实的 Map 键长这样 —— `market:leads:1.2.3.4:1.2.3.4`。**计数行为完全正确**（多出来的那一段对所有请求都一样），但它提醒你：这张表的第三列是**代码字面量**，不是运行时键。不要在 App 里按字面量做键缓存。

两个数字要记住：**登录 5 次 / 15 分钟**（防刷）与服务端软锁 **5 次失败 / 15 分钟**（`MAX_FAILED_LOGINS` / `LOCK_MINUTES`，`buyer-auth.js:83–84`）是**两套独立机制**。前者是每实例的内存桶，后者是写在账号行上的**持久化到期时刻**，理由见 §4.5。

## 4. 身份与鉴权

### 4.1 唯一的身份是服务端会话行，不是 Supabase Auth

公域端**没有** Supabase Auth。整个集市买家体系里，`src/api/supabase.ts` 那个客户端一次都没被使用过——它是租户控制台的登录设备，与 `/market*` 无关。

买家身份的载体是 `mp_buyer_sessions` 表的**一行**：

| 事实 | 出处 |
| --- | --- |
| TTL 30 天 | `server/marketplace-core/services/buyer-auth.js:69` — `BUYER_SESSION_DAYS` |
| 一台设备一行 | 每次登录新插一行，`logout` 只删自己那一行 |
| **故意不是 JWT** | 封禁必须**立刻**生效；自签令牌做不到「服务端一写全场失效」 |
| 凭证形状 | `newSessionToken()` = `randomBytes(32).toString('base64url')`（`buyer-auth.js:101–104`），43 字符 |
| 服务端判定 | `requireBuyerSession()`——**唯一**的凭证判据，七个个人页调用全部走它 |

对 App 的含义：**会话就是一个字符串**，放在安全存储里，随请求带头。没有 refresh token，没有过期重登的 OAuth 流程，没有 `onAuthStateChange` 监听。会话过期就是服务端回 401，App 把它渲染成「请重新登录」，不要自己按本地时间戳猜。

客户端存储键是 `yuanbao.market.buyer.session`（`src/api/buyerAuth.ts:20`），内容是 `{token, expires_at}`。`readSession()`（`:28–42`）会**自愈**：读到过期行顺手删掉，任何异常吞掉。原生 App 里对应的是「读不到就当没登录」，不是「读失败页面崩」。这一行注释值得抄进代码：

> 过期判断只是省一次请求，不是鉴权。

也就是说：**客户端的 `expires_at` 是优化，服务端的 `expires_at` 才是事实**。App 不该因为本地觉得还没过期就跳过 401 的重登分支。

### 4.2 注册与登录

| 调用 | 服务端 | 入参 | 出参 |
| --- | --- | --- | --- |
| `POST /api/market/buyer/register` | `registerBuyer()` `buyer-auth.js:251` | `phone`、`name`、`password`、`lang`、`country`、`consent_marketing`、`device_class` | `{ account, session_token, expires_at }` |
| `POST /api/market/buyer/login` | `loginBuyer()` `:315` | `phone`、`password`、`device_class` | 同上 |

四个边界值由服务端裁决，**不是输入框的 `maxLength`**：

- `cleanName()` `:112` → **2–40 字符**，否则 `400 INVALID_NAME`。
- `cleanPassword()` `:123` → **8–64 字符**，且原文照抄一句必须遵守的话：**「密码只校验长度，不做 trim、不折叠空白」**。App 侧因此**绝不能**在提交前 `trim()` 密码，也不能把空格替换掉——那会让一个合法密码在服务端验不过，而且用户看不出自己改了什么。
- `isConsent()` `:131` → 只接受布尔与 `'true'` 字符串两种形状。
- `normalizeLang()`（`util.js:119`）兜底 `uk`；`country` 宽度 8。

登录分支的**顺序**是钱和安全的事，不是风格：

```
buyer-auth.js:335  →  先判 status === 'suspended'  →  403 BUYER_ACCOUNT_SUSPENDED
buyer-auth.js:340  →  才 verifyPassword
```

被处置的账号**不会**累加 `failed_login_count`。反过来写就等于「平台自己的处置决定，惩罚了这个人反复尝试登录」，是第二个 bug。App 侧要能区分这两个 403 与 401，并且**只对 401 显示「账号或密码不对」**。

密码散列是自描述字符串（`scrypt$N$r$p$salt$hash`，`scryptRun()` `:60`，`SCRYPT_MAXMEM` 64 MB `:76`），所以库里**没有 salt 列**，也不需要「忘记密码重置链接」。公域端目前**没有**邮件/短信找回路径（M8-B 的 SMS OTP 未建，见 §11）。App 的登录页因此不该放「忘记密码」——放了就没有后端可接。

### 4.3 会话生命周期

| 事件 | 调用 | 客户端行为 | 出处 |
| --- | --- | --- | --- |
| 注册/登录成功 | — | **写**存储键 | `buyerAuth.ts:96–120`（超时 20 s） |
| 静默恢复 | `GET buyer/me` | 15 s；失败即「未登录」 | `:122–124` |
| 登出 | `POST buyer/logout` | 15 s，**`finally` 里清本地行** | `:126–139` |
| 改密 | `POST buyer/password` | 20 s，**当前会话继续存活**，其他设备会话被吊销 | `:141–154` |
| 注销 | `POST buyer/close` | 20 s，`finally` 清本地行 | `:156–168` |

两条容易写错的：

1. **改密不是登出。** 服务端在同一支写里吊销**其他**会话，但签发时所在的那一行留着。App 改密成功后应该留在登录态并提示「其他设备需要重新登录」，而不是把用户踢回登录页。
2. **`finally` 里清本地行**意味着「服务端返回失败也要清」。这不是笔误：本地留着一条服务端已经不要的凭证，比强制重登更糟——每次请求都会带一个永远 401 的头。

`last_seen_at` 最多每 5 分钟重戳一次（`SESSION_TOUCH_MS` `:86`）。所以**App 轮询 `GET buyer/me` 不等于每次写数据库**，可以做；但也别指望它当心跳写数据。

### 4.4 `GET /api/market/buyer/me`

出参一律经过 `shapeAccount()`（`buyer-auth.js:169`）：**只有** name（墓碑行为 `null`）、`phone_masked`、`lang`、`country`、`consent_marketing`、两个时钟，以及 M2 的三个计数。

- `stats.*` 的类型是 **`number | null`**（`buyerAuth.ts:67–89` 的 `BuyerMe`）。`null` 说的是「这一格没读到」，不是 0，也不是「没有记录」。界面必须画出这个差别（一条短横 + 「未取到」），把它折成 0 是这个项目记过三次的病根（`safeCount()` / `payment_invoices` / 投影条数）。
- `password_hash` / `phone_e164` / `phone_hash` / `session_token` **不在 SELECT 列表里**，不是「读到了但不下发」。三份白名单：`ACCOUNT_COLUMNS` `:96`（「**绝不含** `password_hash`/`failed_login_count`/`locked_until`」）、`CREDENTIAL_COLUMNS` `:98`、`LOGIN_COLUMNS` `:99`。App 侧无法、也不该拿到任何凭据列。

### 4.5 硬登录门与软锁

**`mp_buyer_gate_enabled` 在现网是 ON**（运营于 2026-10-11 16:30:14Z 从后台 → 系统配置写入，`admin_audit_logs` 里有 `SETTINGS_UPDATE` 行）。也就是说：**未登录的买家点了客服入口，现在是会被挡的**，这不是设想，是当下行为。

判定点只有一个：`resolveBuyerIdentity()`（`services/chat.js:231`），在 `buyerChatStart`（`:259`）与 `buyerChatAppend`（`:327`）**头部**调用，位置在 slug 解析和 `INSERT` **之前**（`:330` 早于 `:335`）。后果是买家侧必须实现的：

| 状态 | 码 | App 的处置 |
| --- | --- | --- |
| 没带凭证 / 凭证太短 | `401 BUYER_LOGIN_REQUIRED` | 弹登录，**不是** toast「请先登录」后什么都不做 |
| 带了但已失效 | `401 BUYER_SESSION_INVALID` | 清本地会话 → 弹登录 |
| 带了但过期 | `401 BUYER_SESSION_EXPIRED` | 同上 |
| 账号被封 | `403 BUYER_ACCOUNT_SUSPENDED` | 一句话说明被处置，**不给重试按钮** |
| 软锁中 | `429 BUYER_LOGIN_LOCKED` + `retry_after_seconds` | 用服务端给的秒数倒计时，不要自己数 15 分钟 |

「短」的门槛是 20 字符：带了的凭证若不足 20 字符按**没带**处理。反过来说，**长度够但没有效**的凭证，在门**关着**的时候也必须被拒——这条规则存在是因为「已登录的买家被静默降级成匿名」会让 `buyer_account_id` 永远是 NULL，而那一列正是卖家侧「这条消息是谁发的」的数据来源。

`localizeError`（前端）把上面四个码归到同一句可重试文案，这个做法值得保留：**一个死于会话问题的买家，不该被提示「请输入有效手机号」**——那等于把平台的登录问题说成用户的输入错误。留资路径同理：`createLead()` 里 `requireBuyerSession()` 在投影读**之前**跑，见 §6.6。

软锁是**持久化**的：5 次失败写 `locked_until = now + 15 min` **并同时清零 `failed_login_count`**（`MAX_FAILED_LOGINS` / `LOCK_MINUTES`，`:83–84`）。服务端规则原文的理由：**「软锁必须有到期时刻」**——一个只累加的计数器意味着任何人都能对别人的号码敲出永久锁。App 侧因此不能自己实现「三次失败锁定」，只能在 429 时显示倒计时。

### 4.6 买家身份四态（卖家看见的，也是买家自己该看见的）

`identityOf(account)`（`chat.js:109`）只有四个值，`verified / anonymous / closed / unknown`：

| 态 | 含义 | 出参 |
| --- | --- | --- |
| `verified` | 活跃账号 | name + `maskPhone()` 结果 |
| `anonymous` | 线程没有 `buyer_account_id` | 门开着之后**新**线程不该再出现这一态 |
| `closed` | 注销墓碑 | `name: null`，掩码 `'****'` |
| `unknown` | **账号读失败了** | 刻意不折进 `anonymous` |

`unknown` 单独存在是这条文档反复出现的那句话的一次落地：把一次读失败说成「这人没登录」，比说错更糟，因为它可解释、不可发现。`IDENTITY_COLUMNS = 'id,name,status,phone_e164'`（`:107`）里没有 `buyer_account_id`，也没有任何凭据列；批量解析走 `identitiesByIds()`（`:141`），**一页一次查询**，不是每行一次。App 若在自己那面展示「对方是谁」，请复用这四个词，不要新增第五态——`closed`（注册过又删了）和 `anonymous`（从没登录）对要不要回复是**两个不同事实**。

### 4.7 两套凭证，永不互换

| | 租户控制台 | 公域买家 |
| --- | --- | --- |
| 头 | `Authorization: Bearer <supabase access token>` | `X-Buyer-Session` |
| 存储键 | `bufang.auth` | `yuanbao.market.buyer.session` |
| 客户端 | `src/api/client.ts`（`apiCall`） | `src/api/buyerAuth.ts` |
| 服务端入口 | `requireBusinessUser()` | `api/market.js:155–157` → `requestContext.buyerToken` |

`api/market.js` 那一行只读一次，`.trim().slice(0, 80)`，注释原文：**「买家凭证只从这里读，绝不看 Authorization」**。`buyerAuth.ts` 每一个调用都带 `skipAuth: true` + `buyerHeaders()`（`:62–65`，全项目**唯一**构造这个头的地方）。

原生 App 里这条规则的落地形式很朴素：**两个独立的存储槽，两套独立的拦截器**。库存端 App 的会话**不能**被公域端读走，反之亦然。共用一个「auth token」变量是这个体系里唯一一种会把买家会话写进卖家安全存储的写法。

### 4.8 注销是墓碑，不是删除

`closeBuyerAccount()` 写**一条** UPDATE，同时翻五样东西：`status='closed'`、`name = CLOSED_NAME`、`password_hash=''`、`phone_e164/phone_hash/buyer_id = NULL`、`closed_at`。两支 CHECK（`chk_mp_ba_pw`、`chk_mp_ba_closed_shape`）**双向**钉住这个形状——分两步写会被数据库拒绝，而在 CHECK 出现之前，半成品状态是被**默默允许**的。

对 App 的三条硬要求：

1. **`CLOSED_NAME = 'deleted'`（`:93`）是数据占位符，不是文案。** 注释原文说得很清楚：界面应按 `status === 'closed'` 出**本地化**文案。四语各写各的，不要把库里的 `'deleted'` 打印给乌克兰买家。
2. **注销不碰业务记录。** 留资、会话、消息一行都不删（`buyer_account_id` 是 `ON DELETE SET NULL`，所以物理删也带不走卖家的线程）。注销后的买家**没有个人页可读**，这是设计，不是 bug。
3. **同一个号码可以再注册。** `phone_e164` 的 UNIQUE 只在「还带着号码的行」之间生效，Postgres 把 NULL 视为互不相等。App 的「该号码已注册」提示不能在墓碑上误报。

### 4.9 租户隔离在公域长什么样

租户控制台靠 `assertTenant(context, tenantId)`。公域端**没有这个函数**，因为买家没有 tenant。这里的隔离是**结构性的**：

- 公域读**只**碰 `mp_listing_public`（§7.1）；
- 出参**只**经过 `shapeCard()` / `shapeAccount()` 这两份白名单形状（§12.4）；
- `listing_id` / `tenant_id` / `mp_category_id` / `pool` 不出现在卡片出参里（`shapeCard()` 的 14 个键没有它们）。

所以公域 App 的「权限」问题只有一个形态：**这个 slug 现在对买家可见吗**。判据是 `isPubliclyVisible()`（§7.2），永远由服务端回答，App 不自行推断，也不凭「角色字符串」决定某个入口是否显示——库存端那条「服务端才是真闸门：403 一律按无权限处理」在这里同样成立。

## 5. 通用约定

### 5.1 错误处理：按 `error.code` 分派，永不按 `message` 分派

公域端的所有出参都走同一个信封（§3.1），App 侧的分派键只有 `error.code`。理由和库存端一样，但公域端多一重：这里的错误文案有四语版本，`message` 会随 `?lang=` 变化，而 `code` 不会。

三条必须照搬的库存端纪律：

1. **只重试 GET，永不自动重试写。** 公域端的三个写全部有业务后果：`POST leads` 会**真的建一张订单**（§6.6），`POST chat/:token/messages` 会给卖家发一条 Telegram 通知，`POST buyer/favorites` 会占掉那 200 个名额之一。重放一次就是一条重复留资或一条重复消息。
2. **退避只打在 `error.retryable` 上**，上限 3 次、`500 << attempt`。公域端可重试的是 502/503 与网络层失败；`409`/`400`/`404`/`403` 重试一万次也是同一个答案。
3. **响应体以 `<` 开头 = 网关返回了 HTML**，按「服务端不可用」处理，不要当 JSON 解析。公域端这一条比库存端更容易撞上：`/api/market/warmup` 之外还有 `vercel.json` 的 SPA 兜底，一个写错的路径会拿到 200 + `index.html`。

### 5.2 分页：一页最多 60 条，越界自动回第一页

`server/marketplace-core/util.js:336` 的 `MAX_PAGE_SIZE = 60` 是公域列表的硬上限，`normalizePagination` (`:338`) 把任何 `page_size` 折进 `[1, 60]`，`pageRange` (`:344`) 算 offset。

**App 不要自己算总页数。** `listProducts` 的回参里有 `total_pages`，而它由服务端算；自己 `Math.ceil(total / 请求时的 page_size)` 会在服务端回落 `page_size` 时错位（请求 100、服务端给 60，于是 App 少算三分之二页）。

一个 PostgREST 特有的坑：`runPagedQuery` (`util.js:357`) 处理 `416 range not satisfiable`。PostgREST 对一个**够不着的 range** 回答 416 而不是空数组，`isRangeError` (`:349`) 判出之后整个查询回落到第 1 页。这意味着：

- 用户翻到第 8 页、数据在此期间被下架到只剩 3 页时，App 拿到的**不是空列表而是第 1 页的内容**，且回参的 `page` 是 `1`。
- **App 必须采纳服务端回参里的 `page`**（`MarketProductPage.page`），不能假定「我请求几就是几」。不采纳的症状是翻页按钮卡住、或者第 8 页显示出第 1 页的商品且总数对不上。
- 这一条也适用于个人页的三块列表：`page_size` 与 `page` 都由服务端回显。

### 5.3 日期与时区：日历只按 Europe/Kyiv 数日子

`util.js:390` 起的 `LISTED_DAY_TIMEZONE = 'Europe/Kyiv'` 是上架日历唯一的时区裁决者。`listedDayBounds` (`:515`) 和 `listedRangeBounds` (`:523`) 出来的都是**左闭右开**区间（`gte` 当天本地零点、`lt` 次日本地零点），而 `resolveListedFilter` (`:564`) 负责把参数折成这个形状并把不合法的输入如实回显成「没有生效」。

三条 App 侧规则：

1. **不要在客户端算「今天」。** 服务端的 `nowIso()` (`:889`) 与 `instantOf()` (`:903`) 是它自己的读数；一台在 UTC-5 的手机上「今天」和 Kyiv 的「今天」在几个小时里不是同一天。日历的 `today` 字段（`listedToday()` `:470` 的服务端回显）就是唯一的那个「今天」。
2. **半开区间不是 +86400000 毫秒。** 服务端刻意取「次日本地零点的瞬时」，所以夏令时切换那天的长度是 23 或 25 小时而区间仍然正确。App 若自己拼区间，必须同样用日历日期而不是毫秒加法。
3. `kind: null` 说的是「这个参数没有生效」，不是 1970 年。`shapeListed()`（§6.3）的 `notes` 会写出是哪一条规则让它没生效。

### 5.4 请求头：公域端只有四个自己带的头

| 头 | 什么时候带 | 谁在生产它 |
| --- | --- | --- |
| `X-Buyer-Session` | 买家已登录时的**读与写** | `buyerHeaders()`（`src/api/buyerAuth.ts:62–65`，唯一的构造点） |
| `X-Sgtm-Token` | `POST /api/market/track`，且只有服务端共享密钥方案启用时 | 服务端；**浏览器与 App 都不该持有它** |
| `X-Request-Id` | 可选，用于把一次点击和服务端日志对上 | App 自己生成，`meta.requestId` 会原样回带 |
| `Content-Type: application/json` | 所有 POST | — |

**公域端永远不带 `Authorization`。** 那是租户控制台的 Bearer（§4.7），`api/market.js` 的 `requestContext` 里没有任何一支服务读它，带着它也不会报错——只会让一个本该匿名的请求看起来像已登录，而这是最难查的一类「为什么这个买家是匿名的」。

`X-Buyer-Session` 的读取侧在 `api/market.js:155–157`：`.trim().slice(0, 80)`，一次读进 `requestContext.buyerToken`。这意味着**超长凭证被静默截断而不是拒绝**——App 侧签发出来的 token 是 43 字符（base64url(32 B)），截不到；若哪一天接到的会话串长度逼近 80，那是数据面问题，不要在这一层猜。

### 5.5 图片：买家侧一个字节都不上传

公域页面上的每一张图片都是**卖家在库存端或集市选品时上传的**，投影到 `mp_listing_public.image_urls` 之后由 `resolvePublicUrl()`（`util.js:782`）折成可公网读的 URL。买家 App 的参与方式只有「显示」。

- `MP_MAX_IMAGES = 5`（`util.js:9`）是单条商品图的上限，第一张是封面。`projectedImageUrls()`（`snapshot.js:77` 起）是「买家页实际拿到哪几张」的唯一判据，它已经过滤掉不合法的引用，所以**出参里的每一条 URL 都是可以直接加载的**，App 不需要二次校验域名。
- `normalizeImageRefs()` (`:863`) 是写入侧的严格判据（只接受本租户前缀的 public storage 对象），`filterImageRefs()` (`:870`) 是投影侧的静默变体（丢掉不合法的而不抛）。买家侧读到的永远是后者的结果。
- ** qualification 文档（`mp-assets` 私有桶）与买家无关**：那是卖家资质件，只有已登录的租户会话能上传、只有平台审核员能通过 180 秒签名 URL 读到。公域 App 里没有它的任何入口，不要为了「统一」预留一个上传模块。

因此库存端那份 `storage_service.dart`（直传 Storage + 签名 URL）在公域端**整体不适用**，对应的模块应该是 `cached_network_image` 只读缓存。

### 5.6 动词只有 GET 与 POST

`api/market.js` 的路由链里**没有 PUT、没有 PATCH、没有 DELETE**，全部写都是 `POST`。这不是省事，是 `vercel.json` 的 CORS 只放 `GET, POST, OPTIONS`：

- `POST /buyer/favorites/remove` 而不是 `DELETE /buyer/favorites/:slug`（`src/api/buyerAuth.ts:258–260` 记的就是这一条）。
- 移除一个本来就不在收藏里的 slug 返回 `removed: false` **且 HTTP 200**——收藏是集合，不是计数器。「点了没反应」和「本来就没有」在服务端是同一个答案，界面上不是：App 应该据此直接把心形改成未收藏，而不是报错。
- 同一个理由管着 `POST buyer/logout`（不是 DELETE）与 `POST buyer/password`（不是 PATCH）。

新增任何路由都按这两条形状走；如果哪天需要真正的 PUT/DELETE，那是一次 `vercel.json` 改动，不是客户端能单方面决定的事。

### 5.7 语言：四语，而 `vi` 读的是英文内容列

`normalizeLang()`（`util.js:119`）兜底 `uk`，`readsEnglishContent(lang)`（`:134`）是「这一档语言读哪一列平台内容」的唯一判据——**`en` 与 `vi` 读英文列**。原因写在 §7 之外的地方一次就够：`mp_categories.name_en` 是 NOT NULL 而 `name_uk` 可空，一条会落在 NULL 的回落链不是回落链。

App 侧的四档语言解析**不共用库存控制台那一套**（那是 `yuanbao.lang` + `navigator.languages`），公域有自己的 `src/pages/market/lang.ts`：

```
URL ?lang=  →  sessionStorage['yuanbao.market.lang.session']
            →  localStorage['yuanbao.market.lang']（只有显式切换才写）
            →  navigator.languages 的整条列表（不是第一项）
            →  uk
```

`MARKET_LANGS = ['uk', 'en', 'zh', 'vi']`，`LANG_OPTIONS[0]` 必须是 `uk`（那是兜底档，控件默认要显示解析已经选中的值）。三条会被违反的：

1. **`?lang=` 必须跨导航携带。** 商品卡是真的 `<a href>`，一次点击就是一次文档加载；不拼参数的那一次点击会把买家从越南语页面扔回自动档。服务端侧同理：每一次请求都要带 `lang` 参数，`localizedTitle()` 才知道读哪一列。
2. **不要把公域语言写进库存端那个键。** 一个卖家可以同时在同一台设备上登录控制台并点开一条广告落地页；共享一个键等于让卖家的偏好决定付费点击看到什么。
3. **`normalizeLang()` 的兜底和浏览器的兜底必须都是 `uk`**（现网两者都是），否则界面显示 A 语言、服务端按 B 语言出文案。

## 6. 模块规格

> 本章每一节给的都不是「功能描述」，而是**这一面在服务端的真实形状**：读哪几个端点、出参里哪些键可以为 `null`、哪些判据不能在客户端重算一遍、哪几种错误码要各说各的句子。行号是 `server/marketplace-core/` 与 `api/market.js` 在当前 `main` 上的位置，用于让你能核对，而不是让你照抄。

### 6.1 首页与类目

| 用途 | 端点 | 服务函数 | 限流桶 | 源码 |
|---|---|---|---|---|
| 类目树 + 每类目供给数 | `GET /api/market/catalog` | `getCatalog()` | `market:catalog:<ip>` | `api/market.js:175–179` → `public.js:133–171` |
| 商品列表（首屏） | `GET /api/market/products` | `listProducts()` | `market:products:<ip>` | `api/market.js:189–193` → `public.js:237–314` |
| 上架日历 | `GET /api/market/listed-days` | `getListedDays()` | `market:products:<ip>` | `api/market.js:198–202` → `public.js:334–364` |
| 跟踪注入配置 | `GET /api/market/tracking-config` | `readTrackingConfigPublic()` | `market:tracking-config:<ip>` 240/min | `api/market.js:183–187` |
| 冷启动探针 | `GET /api/market/warmup` | — | 公开 | `api/market.js:165–173` |

**一个文档里只取一次类目。** `getCatalog()` 在整个公域首页只发一次，类目入口、页脚 SEO 链接、首页筛选 chips 全部共用这一份结果——这是 `MarketSite.tsx` 现在的做法（`CategoryNav.tsx` 的状态被提升到 `MarketSite`，正是为了避免「导航显示当前类目」和「列表按类目筛选」两份真值）。App 里对应的位置是首页容器，而不是每个 widget。

**类目的名称按语言取，而且 `vi` 取的是英文。** 节点名的规则是 `public.js:133–171` 里的这一句：`readsEnglishContent(lang) ? name_en : (lang === 'zh' ? name_zh : name_uk)`。三个词表都在出参里（`name_zh` / `name_uk` / `name_en`），客户端**不要**自己按语言挑——挑错一次就会和「买家页 enforcing 的禁售词表」用另一套词，那是卖家侧已经发生过一次的分裂（见 §5.7）。

**类目上的数字必须来自 RPC，不是数行。** 计数只从 `rpc('mp_category_listing_counts')` 来（`public.js:133–171` 里唯一的一条计数读，缺行即 `dbFail`），理由是 PostgREST 单页上限 1000 行，Node 侧数行「供给过千之后 chip 上的数字会安静地少报」。根类目的数是由子类目向上滚上来的（按 `depth` 倒序），**为的是「chip 上的数量要和点进去看到的一致」**。App 侧的纪律因此是：

- 类目 chip 上的数字**直接打印出参**，绝不用「本页返回了几条」代替；
- 空结果的补救类目条只给 `listing_count > 0` 的根类目——把空类目做成出口是最坏的空状态；
- 类目是**视图不是页面**（见 §9 与 §11），所以一个类目页没有任何「独立地址」的语义，收藏/分享一个带 `?category=` 的地址等于分享首页。

### 6.2 列表与筛选

| 参数 | 类型 | 服务端处理 | 说明 |
|---|---|---|---|
| `q` | string | `textSearch('search_tsv', …, { config: 'simple', type: 'plain' })` | 投影表用 `simple` 分词（无词干还原），**查询侧必须同配置**；`type:'plain'` 走 `plainto_tsquery`，天然免疫 FTS 语法字符 |
| `category` | slug | `resolveCategoryIds()` `public.js:178–188` | slug → {自身 + 子类目} 的 id 集合，列表与日历共用这一支 |
| `seller` | slug | `eq('seller_slug', normalizeText(query.seller, 80))` | **是 slug，不是店名**（店名是卖家可以改的内容） |
| `price_min` / `price_max` | number | `gte/lte('price_ukr')` | 见 §6.10 的 300 ms 提交 |
| `in_stock` | `'true'` | `gt('stock_qty', 0)` | 只有字符串 `'true'` 生效 |
| `online_pay` | `'true'` | `eq('supports_online_pay', true)` | 同上 |
| `lead_time_max` | number | `lte('lead_time_days')` | |
| `sort` | `recommended\|newest\|price_asc\|price_desc\|stock` | `SORTS` `public.js:52–58` | 未知值回落 `recommended`，并把生效值回显在出参 `sort` |
| `page` / `page_size` | number | `normalizePagination` | 见 §5.2，一页最多 60 |
| `lang` | `uk\|en\|zh\|vi` | `normalizeLang` | 兜底 `uk` |
| `listed_day` / `listed_from` / `listed_to` | 日期 | §6.3 | 与 `q`/`category` 组合，不互斥 |

**默认档是唯一会藏东西的档。** `hideMuted = effectiveSort === 'recommended'`（`public.js:237–314`），源码里的话值得原样记下来：「只有默认档隐藏 muted：买家主动按价格／库存／最新来筛，是他自己的意图，平台排序没有权利把他点名要看的供给藏掉一条」。所以 App 的筛选面板**不能**把「推荐」当成一个不可选的默认状态藏起来——它和其它四档一样是一档，而且换档会真的改变条数。

**排序链是三级。** `sort.column` → `sort.tie` → `.order('listing_id', { ascending: true })`。最后一级是**必要的**：`rank_score` 在 `/api/cron` 写回之前每行都是 0，没有 `listing_id` 兜底，同一页的分页会在两次请求之间随机重排。

**`recommended` 读的是存好的列，不是现算的分。** `public.js:46–51` 的文档块说明这四档排序列**只由 `/api/cron` 的 `recomputeRanks()` 写**，读路径永不计算，「排序列和排序代码可以分两次发布而中间不出空档」。App 侧的唯一后果是：**分数会过期**。`rank.js` 的 `RANK_STALE_HOURS` 是 48，而这个项目的 GitHub Actions 定时任务实测延迟 3–7 小时，所以「刚上架的商品排在第三屏」不一定是 bug。

**卡片形状是一个白名单，14 个键。** `shapeCard(row, lang)` 在 `public.js:106–131`，出参恰好是 `slug, seller_slug, seller_name, title, sku, price_ukr, currency_symbol, image_url, image_count, min_order_qty, lead_time_days, supports_online_pay, support_uk, in_stock, rating, published_at, url`（`title` 由 `localizedTitle()` `:101–104` 折成单一字段）。`listing_id` / `mp_category_id` / `pool` / `tenant_id` **从不出去**。三条会为 `null` 且各自有语义：

- `sku`：`row.sku || null`。「NULL 说的是这一行还没有编码，界面据此整行隐藏；空串一律折回 NULL」。
- `lead_time_days`：原值。`null` 是「卖家没填交付周期」，不是「当天发货」。首页卡片把这一格留空，详情页才允许显示「未标注」。
- `rating`：`!= null ? Number : null`。**不要把 `null` 打成 `0 分`**——那是「还没有评分」和「评分很差」两个相反结论共用一个数字。

**`is_promoted` 是列表层派生的，不是 `shapeCard` 的字段。** `public.js:294–303` 的文档块是这一条的理由：同一个 `shapeCard()` 服务相关推荐、店铺页、收藏列表，在那里「推广」会是一句假话；而**显式排序不摘掉这个标注**（这一小时这一格确实卖出去了）。判据是 `isPaidSlotPool(row.pool)`，与埋点 `slot_kind`、卖家页签 `slot_granted_now` 是同一个函数——三处任何一处「顺手」写成 `pool !== 'core'`，都会把卖家自己点的免费刷新说成收过钱，而那一句话在买家侧是**广告披露**。

> 现网读数（2026-10-30 更新）：保险丝 **`ad_enabled` 已经翻开**（业主 10-28 05:21Z），所以「关着所以恒 false」这个理由已经不成立了 —— 但**结论暂时没变**：`is_promoted` 现网仍全为 `false`，因为唯一那一行 `ad_campaigns` 是 `canceled`（10-29 10:50:43Z 建、10:51:31Z 取消），没有任何行拿到 `pool='paid_boost'`。差别很重要：**开闸之后挡住标注的是「没人买位」，不是「位不存在」**，而前者随时会翻。App 要有这一格的位置，并且不能因为今天看不见就不写。详见 §11.1 A1 与 §11.3。

**空默认流的补救是设计的一部分。** `public.js:284–290`：默认排序返回 0 条时，会带 muted 重查一次，「降池把这一屏能给的供给全藏掉了：宁可让买家看到低分商品，也不能给一个花钱买来的流量渲染空页…它只在原本为 0 的结果集里生效」。App 侧必须能区分这两种「补救」：

1. **降权补救**（默认档 0 条 → 展示低分供给）：出参还是 `items`，没有别的标志位，**不要**为它做特殊 UI；
2. **筛空补救**（§6.10）：结果 0 条**且**确实做了收窄，出参与请求参数都正常，靠 `total === 0` 触发。

### 6.3 上架日历

`GET /api/market/listed-days`（`public.js:334–364`）是首页「哪一天有上新」的唯一数据源。文档块 `:316–333` 给的理由是结构性的：公域一屏最多 60 条，前端只能数出「这一页」，那是一张会撒谎的日历。

出参形状见 §12.4 的 `MarketListedDayFacet`，三个决定必须照做：

- **窗口固定 30 天，永不跟着选中日缩短。** 选中日只是回显成 `selected`。缩短窗口会让日历在点完之后自己变形。
- **`withMuted = true`。** 否则日历的数与「点进去那一屏」的数差一行——而带日期的那一屏走 `newest`，`newest` 不隐藏 muted，所以两边本来就一致，只有 facet 必须一致。
- **倒序有界扫 ⇒ `truncated` 为真时这一格是下界。** 「读不到」折成「没有」是这个项目记过三次的病根（`safeCount()` / `payment_invoices` / 投影条数）。App 侧的画法：`truncated` 时格子仍画数字，但要能提示「至少 N 条」。

`missing || !window` 时提前返回 `reason: 'category_not_found' | 'window_unavailable'` 且 `window: null`，**日历整块不渲染**——宁可不画日历，也不能退化成全表扫。

时区口径见 §5.3：`LISTED_DAY_TIMEZONE = 'Europe/Kyiv'`（`util.js:390`），区间是**半开**（`listedDayBounds :515` / `listedRangeBounds :523`），`resolveListedFilter :564` 是唯一裁决者，`listedToday()` `:470` 才是「今天」。

`shapeListed()`（`public.js:223–235`）把生效窗口回显成 `{kind, day, from, to, days, bounds:{gte,lt}, notes}`；`kind: null` 说的是「这个参数没生效」，不是 1970 年；`notes` 记的是被忽略的参数（`listed_day_wins` / `listed_range_swapped`），「因为分享链接会被人手改，『你带的这两个没有生效』必须是读得出来的事实」。

### 6.4 详情页

`GET /api/market/products/:slug`（`api/market.js:204–208`，独立桶 `market:detail:<ip>`）→ `getProductBySlug()` `public.js:366–438`。

**这一支有两次 `Promise.all`，App 不要拆成串行。** 第一次并发「投影行 + 平台开关」（「开关与投影行互不依赖…串行时详情面要 6 个往返，而其中 2 个本来可以并进第一个」）；第二次并发「类目 / 同类相关推荐（`.gt('stock_qty',0).order('published_at desc').limit(8)`）/ 该卖家在架条数」。

字段语义里三个 `null` 要按句子画，不按 0 画：

| 字段 | `null` 的含义 | 画法 |
|---|---|---|
| `ttfr_hours` | 还没有可测的留资响应 | **整行消失**。写成「0 小时内回复」等于替卖家承诺一个他没演示过的速度 |
| `seller.listing_count` | 「这一格没读到」 | `—`。`listingCount = error \|\| count === null ? null : count`，源码原话：「旧的 `sellerCount \|\| 0` 把它们压成同一个数字，而 0 是买家会当成事实读出来的那一个」 |
| `rating` | 无评分 | 不画星级 |

`≥24 h` 的中位数换成天（「3.5 天」和「72 h」都不如「3.5 天」好读，手机上更甚），不足 1 小时显示 1 小时——这条显示规则在 Web 上已生效，App 照做即可，别改口径。

> 2026-10-30 起 `ttfr_hours` 的**来源变宽了**（值域没变）：卖家的「已成交 / 已拒绝」现在也计首响，而一张集市留资生成的订单被做完时，服务端会把订单真正的 `completed_at` 补成首响时间。所以这一行会比以前更常出现非 `null`，而**它的语义仍然是「这家回复过」**，不是「这家发货了」——文案别顺手改成「已发货」。`null` 的画法一字不改。

出参还带 `description`（按 `readsEnglishContent` 选列）、`description_en`、`image_urls`、`spec_attrs`、`category {slug, name_uk, name_en}`、`related[]`、`url`，以及两个开关位 `chat_enabled` 与 `buyer_gate_enabled`。**后者只是同一个判据的值，不是第二个判据**：登录门仍然只由 `resolveBuyerIdentity()` 判（见 §4.5），这一面只是让 App 能在门开着时先弹登录而不是让买家打完字再吃 401。

slug 不存在或行不在投影表 ⇒ **404 `LISTING_NOT_FOUND`**。注意这是**列表页可以合法点进来**的一个终态（投影行在 `/api/cron` 两次扫之间被隐藏），所以详情面拿到 404 的正确反应是「这个商品已经不在公域了」的整页态 + 回首页，而不是 toast。

### 6.5 店铺页

`GET /api/market/sellers/:slug`（`api/market.js:210–214`）→ `listSellerProducts()` `public.js:440–462`。

```
visibleOnly + eq('seller_slug', slug) [+ in_stock==='true' → gt('stock_qty',0)]
order: published_at desc
空结果 → 404 SELLER_NOT_FOUND
seller.name 取自 data[0].seller_name（一次读，不发第二次查询）
```

**默认流 ≠ 店铺页，这不是 bug。** 这一面**不隐藏 `muted`**（列出全部可见行），而首页默认档隐藏。本项目的一个验收台第一版就是断言两侧条数相等而在现网失败（1 vs 2）：目标租户一条 `active/muted`、一条 `active/core`。App 侧的后果是真实的——买家从「只看这家」看到 1 条，进店看到 2 条，所以那个 chip 必须同时给出进店入口（Web 已经这么做）。

`404 SELLER_NOT_FOUND` 与详情面的 `LISTING_NOT_FOUND` 是两个不同的终态：前者可能是 slug 打错，也可能是这家一条可见供给都没有了。

### 6.6 留资下单

`POST /api/market/leads`（`api/market.js:216–223`，桶 `market:leads:<ip>`）→ `createLead()` `public.js:558–757`。这是公域**唯一**会真写卖家业务表的买家端点：写 `mp_leads` 并走 `process_order_v2` 生成「备货前」订单（`is_preparing=true` 不动库存，电话确认后再备货）；**金额一律服务端按投影表价重算**。

请求体：

```
slug              必填，normalizeText(..., 120)（也接受 listing_slug）
phone             匿名路径必填；登录路径不接受（见下）
name              可选，80
email             可选，normalizeEmail
quantity          可选，optionalInt {min:1,max:1000000}，默认 1
box_count         可选，整箱数
piece_count       可选，散件数
demand_note       可选，500（也接受 note）
consent_marketing 可选，true 或 'true'
use_saved_contact 可选，true 或 'true' —— 已登录买家「用我保存的号码」的意图
```

**`use_saved_contact` 是意图，不是值。** 掩码过的号码（`+380****88`）过不了 `normalizePhone()`，所以「用我保存的手机号」这件事只能在服务端做：凭证仍由 `requireBuyerSession()` 判一次（它是唯一凭证判据，这里不查第二遍表），号码与联系人从账号行取，明文只进 `mp_leads` / `customers`，一个字节都不回浏览器。联系人保留买家当场改写的余地——表单里填了就用填的，空着才回落到账号名。

**顺序是钱与体验的交界，不能换。** `requireBuyerSession` 在校验号码**之前**跑：「无效 / 过期 / 封禁一律由 `requireBuyerSession` 抛出（401 / 403），不能退化成『请输入有效手机号』——那会把一次登录问题说成买家的输入错误」。App 侧要按码分派：`BUYER_LOGIN_REQUIRED` / `BUYER_SESSION_INVALID` / `BUYER_SESSION_EXPIRED` / `BUYER_ACCOUNT_SUSPENDED` 全映射到同一句「请重新登录后再提交」，并且**不要**清空买家已经打过的字段。

校验链与错误码（按执行顺序）：

| 步 | 判据 | 码 | HTTP | 买家文案 |
|---|---|---|---|---|
| 1 | 会话/号码 | `BUYER_*` / 无效号码 | 401/403/400 | 重新登录 / 请输入有效手机号 |
| 2 | 投影行存在且可见 | `LISTING_NOT_FOUND` | 404 | 该商品已不在公域 |
| 3 | `stock_qty > 0` | `OUT_OF_STOCK` | 409 | 该商品暂时缺货 |
| 4 | `quantity ≥ min_order_qty` | `BELOW_MIN_ORDER` + `details.min_order_qty` | 400 | 起订量 N |
| 5 | `quantity ≤ stock_qty` | `OVER_STOCK` + `details.stock` | 400 | 现有库存 N |
| 6 | 私有申请行仍 `published` | `LISTING_UNAVAILABLE` | 409 | 该卖家暂时不接受新需求 |
| 7 | 商品行存在且未软删 | `PRODUCT_UNAVAILABLE` | 500 | 服务端问题，可重试 |
| 8 | 租户状态在 `VISIBLE_STATES` | `TENANT_UNAVAILABLE` | 409 | 该卖家暂不可接单，请联系平台客服 |
| 9 | 客户行建/找到 | `CUSTOMER_FAILED` | 500 | 服务端问题，可重试 |
| 10 | `process_order_v2` | 见下 | 400/409 | 透传 `orderResult.message` |

第 6–8 步是「投影说在售、私有说不在售」的中间态，也是本项目里最容易被误报成 bug 的一段。第 10 步是**整个公域唯一保留上游 `.message` 回显的地方**（`public.js` 原话）：「这不是错误对象，是 `process_order_v2` 的**返回值**，文案由我们自己写在 SQL 里（`order-stock-message-v1` 把它改成『库存不足：名称 / SKU（需要 N，现有 M）』）。买家要看到的就是这一句」。**所以这一句必须原样上屏，不要翻译、不要改写成通用「提交失败」。**

箱/散算法：`upb = units_per_box > 1 ? units_per_box : null`，`finalQuantity = boxCount*upb + pieceCount`，随后再查一次 `OVER_STOCK`。`unitPrice = Number(listing.price_ukr || 0)`，`subtotal = (unitPrice*finalQuantity).toFixed(2)`——**单价与库存都来自服务端，永远不用 App 里那一屏的数字**。

`leadCurrency = projectedCurrencySymbol(listing.currency_symbol)`：「留资行与回显只算这一次：两处各折一份会长出『账上写 UAH、屏幕印 $』这种对不上账的留资」。App 直接打印出参的 `currency`。

出参（`public.js:735–757`）：

```
lead_id
order_number          ← 唯一可能为 null 的字段
seller_name
quoted_amount
currency              ← 符号
quantity
contact_masked        ← maskPhone()
next_step             ← 固定话术：卖家将在 24 小时内电话联系确认，请保持手机畅通
```

`order_number` 为 `null` 的原因是 RPC 只回 `order_id`，订单号要回查一次；回查失败不影响留资已经成立。**成功屏因此只能「整行隐藏」，不能印一个空。**

**这个端点绝不自动重试**（§5.1 的第一条在这里最贵）：一次成功的 `POST /leads` 在卖家 `orders` 里生成一张真单，重试两次等于打两次电话。

### 6.7 网页客服

| 用途 | 端点 | 函数 | 源码 |
|---|---|---|---|
| 开线程 | `POST /api/market/chat` | `buyerChatStart()` | `api/market.js:228–235` → `chat.js:259` |
| 读线程 | `GET /api/market/chat/:token` | `buyerChatGet()` | `api/market.js:237–241` → `chat.js:314` |
| 发消息 | `POST /api/market/chat/:token/messages` | `buyerChatAppend()` | `api/market.js:243–250` → `chat.js:327` |

**买家唯一拥有的是一个随机 43 字符 base64url `buyer_token`**，线程只按它寻址；**没有任何响应携带 `tenant_id` / `listing_id`**。它存在 App 自己的存储里（Web 侧是 widget 自己的存储），键名建议对齐 `yuanbao.market.chat.token`，并按「商品 slug → token」存一份映射，因为从个人页「继续对话」回来时靠的是 token 而不是重新开线程。

三条不能改的行为：

- **开线程会重跑留资的可见性校验**（`resolveVisibleListing()` `chat.js:202`：投影行在 `VISIBLE_STATES` **且**私有申请 `status='published'`）。所以一个已下架商品的客服入口返回 409 是正确行为，不是接口 bug。
- **消息正文过禁售词典**：`assertNoBannedTerm()` `chat.js:62` ⇒ **422**。App 必须把 422 和「发送失败」分开展示，否则买家会反复点同一个被拦的句子。
- **门是硬门。** `resolveBuyerIdentity()`（`chat.js:231`）在 `buyerChatStart` 和 `buyerChatAppend` 的最前面，**先于** slug 解析和 INSERT，所以一次被拒的匿名尝试**不产生任何行**。带凭证（≥20 字符）即使门关着也必须能解析到活会话；已登录买家绝不被静默降级成匿名。

长度与上限：`MAX_MESSAGE_LEN` 2000（`:37`）、`THREAD_LIMIT` 100（`:38`）、`cleanMessage()` `:55`、系统话术 `SYSTEM_TEXT` `:40`。

**没有 Realtime，两侧都是轮询。** 买家侧开线程 6 s、关线程 15 s；卖家侧列表 30 s、开线程 15 s 且 `document.hidden` 暂停。App 等价：`AppLifecycleState.paused` 时停轮询，恢复时立即拉一次。

**`after` 游标而不是偏移。** `loadThread(service, conversationId, afterId)`（`chat.js:81`）——增量拉取传最后一条消息 id，返回增量。这是「新消息不重复、不丢」的唯一形状，不要写成 `page`/`page_size`。

`getMarketChat(token, after?)` 是**唯一不带凭证的客服读**（Web 侧 `src/api/market.ts:423–429` 刻意不加 `buyerHeaders()`）：凭 token 就能读自己的线程，加不加都一样。开线程与发消息**必须**带 `X-Buyer-Session`（门开着时不带就是 401）。

卖家侧半（`/api/business/marketplace/*`、Telegram 绑定、`ChatsTab.tsx`）是租户控制台，不在买家 App 范围内。

### 6.8 买家账号与个人页

账号侧七个写与一个读（全部在 `api/market.js:256–299`）：`register` / `login` / `me` / `logout` / `password` / `close`，加上 M7 的个人页五读两写。全部走 `X-Buyer-Session`，客户端传输层是 `src/api/buyerAuth.ts`（309 行，形状照抄即可）：

| 端点 | 方法 | 客户端封装 | 服务函数 | 行号 |
|---|---|---|---|---|
| `buyer/register` | POST | `registerBuyer` 20 s | `registerBuyer()` | `api/market.js:256–263` |
| `buyer/login` | POST | `loginBuyer` 20 s | `loginBuyer()` | `:265–272` |
| `buyer/me` | GET | `getBuyerMe` 15 s | `getBuyerMe()` | `:274–278` |
| `buyer/logout` | POST | `logoutBuyer` 15 s | `logoutBuyer()` | `:280–284` |
| `buyer/password` | POST | `changeBuyerPassword` 20 s | `changeBuyerPassword()` | `:286–291` |
| `buyer/close` | POST | `closeBuyerAccount` 20 s | `closeBuyerAccount()` | `:293–299` |
| `buyer/conversations` | GET | `listBuyerConversations` | `listBuyerConversations()` `chat.js:412` | `:304–308` |
| `buyer/leads` | GET | `listBuyerLeads` | `listBuyerLeads()` `buyer-auth.js:633` | `:310–314` |
| `buyer/favorites` | GET | `listBuyerFavorites` | `:690` | `:316–320` |
| `buyer/favorites/slugs` | GET | `listBuyerFavoriteSlugs` | `:729` | `:322–327` |
| `buyer/favorites` | POST | `addBuyerFavorite` | `:748` | `:329–334` |
| `buyer/favorites/remove` | POST | `removeBuyerFavorite` | `:771` | `:336–341` |
| `buyer/favorites/migrate` | POST | `migrateBuyerFavorites` | `:794` | `:343–349` |

**个人页是四态而不是「空」。** `logged_out` → 登录引导（本地收藏照常可用）；`unknown` / `invalid` / `expired` → 一行重新登录；`suspended` → 它自己的一句话。读失败永远不印成「没有记录」——与 §6.4 的 `null` 是同一条纪律。

**收藏是服务端成员真相，本地是缓存。** `wishlist.ts` 的形状是一个模块级单例状态机：未登录用本地、登录用云端、迁移只发**差集**、`yuanbaokucun.market.wishlist.migrated` 记住本机已经交过哪些 slug（所以下一次迁移发 0 个请求），乐观写、失败回滚。三条不能改：

- `BUYER_FAVORITES_MAX` **200**（`409 FAVORITES_FULL`），本地那一侧的上限必须与它相同，否则「云端能装下、本地装不下」会变成一个静默丢收藏的 bug；
- 重复添加回 `{already: true}` 而**不插入**（`uq_mp_bfav` 是判据）；
- **`removeBuyerFavorite` 不受可见性门控制**——已下架商品的收藏必须还能取消，否则那颗心是一个永久谎言。

`listing_visible`（`BuyerFavoriteRow extends MarketCard`）说的是「现在还能不能点进去」。**不可见的收藏行仍然列出来，但不给链接**（`ProductCard` 的 `disabled` prop：变成一个不可点的卡片，而不是一个指向 404 的链接）。它是买家自己的记录，所以不能从列表里删掉——这一条与 §7.2 的「一个可见性判据」是同一件事的两个面。

`listBuyerFavoriteSlugs`（成员判据那一读）**刻意不做可见性判断**：已经点亮的心必须保持点亮，服务端不该静默丢掉一个成员。

留资那一块的指针是 `buyer_id`（`mp_buyers` 伪名行）**不是** `buyer_account_id`——`mp_leads` 没有账号列。所以一个注销墓碑会在**账号**上把 `buyer_id` 置 NULL（那个人再没有可读这一块的入口），而留资行保留自己的 `buyer_id`（那是卖家的业务记录）。`listBuyerLeads` 在 `!account.buyer_id` 时返回空信封，选择列表里**不含** `contact_phone`，并且用 `mp_listings!inner(...)`——`!left` 的子过滤只会裁子行、不会裁父行，会安静地列出「申请已经没了」的留资。

会话那一块出参带 `conversation_token`，是**设计出来的出参**：App 用它从个人页**续上**已有的线程（Web 是 `/market/p/<slug>?chat=open`），而不是对同一个商品开第二个线程。它不选 `seller_unread`（那个数字属于卖家，出现在买家屏幕上只会引起误解），也不带 `tenant_id` / `listing_id`。

### 6.9 埋点与归因

**两支通道，两条表，刻意不重叠。** `mp_events` 是 append-only 行为流水（一屏一批发一次），`mp_attributions` 是一次落地的 last-click 存储。三条把它们分开的规则：

- `conversion_stage` / `converted_at` **绝不从浏览行为写**。它们的消费者是 `idx_mp_attr_pending_upload`（广告离线回传队列），从行为填会把每一个未转化会话推进上传队列。唯一的公域写者是 `createLead` 尾部 `public.js:727–733`，且带 `.is('converted_at', null)`。
- **没有 `order_created` 事件。** `createLead` 总会建单，所以 `mp_leads.order_id` 已经是权威。
- 加一类事件是**三处一起改**：两个 SQL 文件的 CHECK、`EVENT_TYPES`（`services/events.js:24–33`）、`MarketEventType`（`src/api/market.ts:319–328`）。漏 CHECK ⇒ 插入被拒；漏后两者 ⇒ 漏斗安静地永远不计它。

现网事件词表**恰好 8 类**：`impression, card_click, product_view, search, filter_change, lead_form_open, lead_form_submit, chat_open`。

写侧：`POST /api/market/events`（`api/market.js:362`，桶 `market:events:<ip>` 120/min，单批 ≤80 行 —— `MAX_BATCH` `events.js:46`「一屏最多 60 张卡片，留出余量同时挡住刷量」）。`recordMarketEvents(body, requestContext)`（`:122–191`）逐字段：

```
session_id            必填 → 400 MISSING_SESSION
events[]              必填 → 400 MISSING_EVENTS；>80 → 413 EVENT_BATCH_TOO_LARGE
event_type            不在 8 类词表 → 400 UNKNOWN_EVENT
listing_slug          LISTING_SCOPED 的 6 类必须解析出 slug（只查 mp_listing_public），
                      解析不到 → 这一行被丢掉，不写孤儿行
source                home | search | category | seller | related | detail；词表外 → null
position              0..200
page                  1..500
query                 80    sort 20    country 8    user_agent 300
device_class          mobile | desktop | tablet（客户端自报，:147–149）
slot_kind             服务端从 pool 派生（:84–87），客户端不送
```

响应 `{recorded, skipped}`；`skipped`「用于发现埋点漂移，不含任何买家信息」。**脏行是被跳过而不是抛错**——一行脏数据不能丢一整批。

**读侧唯一通道是 `src/pages/market/analytics.ts`**，App 应复刻它的四条机械规则：队列 20 行或 1.5 s 冲刷；**点击与卸载用 `keepalive: true` 冲刷**（商品卡是硬跳转，普通 `fetch` 会在飞行中被杀掉，CTR 的分子会静默消失——这就是 `apiCall()` 的 `keepalive` 选项存在的唯一理由：丢掉 AbortSignal、超时压到 8 s）；曝光来自 40% 可见的 IntersectionObserver，按 `${source}|${view}|${position}|${slug}` 去重、会话内 500 键封顶，所以一批等于一屏。没有用 `sendBeacon`，因为它会在 `apiCall` 错误信封之外长出第二条形状不同的通道。

**三处刻意不发事件**：`prefetch.ts`（卡片停留 120 ms 鼠标 / 250 ms 触摸预取详情——悬停既不是点击也不是浏览，计进去等于用买家没做过的动作填 CTR 分母）、`MarketAdStrip.tsx`（平台自己主动渲染的横幅会给卖家扣费）、`getMarketListedDays`。App 里对应的是「详情预取」和「首页推广滚动条」两个模块，它们**不能**订阅事件通道。

归因写侧 `POST /api/market/track`（`api/market.js:351–357`）→ `trackAttribution()` `public.js:827–875`：只接受同源 referer，或服务端来源（`SGTM_SHARED_SECRET` + `X-Sgtm-Token`）；IP 只存哈希；`utm_source` / `utm_medium` 先归一再入库（「否则一条 `utm_source=ad` 就能把自然流量混进付费桶」），`utm_campaign`/`term`/`content` 留自由文本（「计划名里出现『ad』不算说谎」）。落库列全清单与宽度见 `public.js:827–875`，其中 `fbc` 由客户端**合成**成 `fb.1.{ms}.{fbclid}`，`fbp` 读 `_fbp` cookie 但 `hasAdParams()` **不认它**（否则每个回访客都会触发一次 `/track`），`ttclid` 透传。

`POST /api/market/track` 有同源门：`trackAuthorized()`（`api/market.js:115–124` ⇒ `403 TRACK_FORBIDDEN`），`:98–114` 的话要留着：「这一条挡的是浏览器被别的网站驱使这条路，挡不住 curl —— 刷量真正兜底在排序侧」。`sameHost`（`:90–96`）「取不到就返回 false —— 绝不把脏值当成同源」。**原生 App 不是同源**：它落 `/track` 必须走 `APP_CORS_ORIGINS` 白名单（`api/market.js:69–87`），或者干脆由 H5 落地页那一跳负责埋归因、App 只上报后续事件——这是架构决定，见 §11。

### 6.10 搜索与空结果补救

**价格区间 300 ms 静默提交**（或 Enter，或**卸载时**——关掉移动筛选抽屉本身就是一次卸载，丢掉这次冲刷等于丢掉买家刚设的条件）。逐字符提交会让「1200」变成四次公开查询，并给买家看他根本没输入的区间。

**每一轮新筛选都要骨架屏**，不是只有第一轮：把上一轮的结果留在一个新条件下面，是一个对「哪条结果是哪个查询的」说谎的网格。

空结果的补救块只在**结果为空且确实被收窄**（`q` / 价格 / `in_stock` / `online_pay` 至少有一个）时发请求。空类目不带价格区间也还是空的，那次请求既浪费、标题又会渲染在空位上。补救读失败时**只藏起这一块**，不碰主错误态。

补救网格用**自己的 `view` 键**（`salvage|<category>`，`page: 1`，`sort: 'recommended'`）。这里必须说清一件事，因为它和文档别处的说法不一样：**`view` 是客户端去重键，不是持久判别字段**。现网 `mp_events` 没有 `view` 列，`recordMarketEvents()` 也从不接受一个 `view`，所以补救曝光存下来就是 `source='home'|'category'`，和主网格一样；`mp_listing_engagement()` 按 `listing_id` 聚合时**根本不看** `source`。也就是说这些曝光**会**进同一支商品的 CTR 分母。这在当前形状下无害，因为补救网格**只在主网格为空时**渲染，一条卡片不会在同一轮里被数两次。真正要 `source` 与 `sort` 都独立可分，需要一列持久判别字段（新列 + 合并 + 授权那一整套），为三条供给不值得做。

选类目 chip 时丢掉所有收窄条件但**保留 `sort`**（阅读顺序不是收窄条件），并且不额外记一次 `filter_change`——因为「选类目」在 Web 上收敛到一个统一的入口点，App 也应只在一个地方记。

## 7. 关键业务不变量

本章是全文的承重墙。第 3–6 章讲的是「每个端点怎么用」，这一章讲的是「**哪些规则一旦被绕过，数字就会开始撒谎**」。这些规则在服务端都已经成立，App 侧的任务是**不破坏它们**，而不是重新实现它们。八条里每一条都有唯一的实现位置，App 侧唯一会犯的错是「在客户端再算一遍」。

### 7.1 投影表是唯一的跨域通道

`server/marketplace-core/snapshot.js:14–18` 的注释原文是这套系统的公域宪法：

> 公域投影（§2.2 唯一跨域通道）。私有表 → 投影表只允许经过本文件的白名单列，任何新增字段都必须显列出，严禁把 products/inventory/orders 的原始行整体 spread 进来。

对 App 的直接含义只有一句：**公域端 App 绝不直连 Supabase 的任何表。** 库存端那套「读也走后端、只有鉴权直连 Supabase 客户端」的纪律在公域端更进一步——公域买家根本没有 `users` 行、没有 `tenant_id`、不在订阅状态机里（`users.email` 是 NOT NULL UNIQUE，`requireBusinessUser()` 会 403 一个无租户的 profile），所以公域端**不存在**任何一条「直连读取」的合法形状。全部数据只从 `https://www.torgseek.com/api/market/*` 出来。

这条纪律不是洁癖。买家能看到的每一个字段都是 `snapshot.js` 显式列出的投影列：`title_uk` / `title_en` / `price_ukr` / `currency_symbol` / `stock_qty` / `image_urls` / `lead_time_days` / `sku` / `seller_name` / `seller_slug` / `pool`……而 `cost`、`inventory.location`、`orders`、`customers` 的原始行**结构上不在投影表里**，所以「App 少显示一个内部字段」不是靠 review 保证的，是靠表里没有保证的。反过来也成立：**一个字段要出现在公域，必须先出现在投影表**，而不是先出现在 App 的请求里。

一处诚实的例外，必须写清，否则 §3 那张端点表会被读成「公域只碰投影表」这句假话：`createLead()`（`public.js:558` 起）在校验完投影行之后，**在服务端内部**回查了 `mp_listings`（私有申请行，`:631` 附近，`.eq('id', listing_id).eq('tenant_id', tenant_id)` 双条件）、`products`（`.is('deleted_at', null)` 并 embed `inventory(quantity)`）、`tenants`（`VISIBLE_STATES.includes(resolveTenantState(tenantRow))`）与 `customers`（按 `(tenant_id, phone)` 找或建），才能生成那张「备货前」订单。这是**服务端内部的跳跃**，买家侧一个字节都看不见，出参仍然只有 §6.6 列的那七个键。所以正确的说法是：

- **公域读路径**只碰 `mp_listing_public`；
- **公域写路径**（留资）在服务端会回到私有表，因为订单本来就必须落在私有表里；
- 无论读还是写，**App 都只认识 `/api/market/*`**。

### 7.2 「现在能不能被买家看到」只有一处裁决

`snapshot.js:366–367`：

```js
export function isPubliclyVisible(tenantState, privateStatus) {
  return VISIBLE_STATES.includes(tenantState) && privateStatus === 'published';
}
```

`VISIBLE_STATES` 在 `snapshot.js:20` 定义为 `['active', 'trial', 'expiring']`，并在 `snapshot.js:370` 与 `isPubliclyVisible` 一起导出（同一行：`export { sellerSlugFor, VISIBLE_STATES };`）。已验证：这两个符号都确实可从模块外读到，§11 里不再对这一条留疑问。

这一句是**五个地方共用的同一个判据**，App 侧是第六个使用者，不是第二个实现：

| 使用者 | 位置 | 它在回答的问题 |
| --- | --- | --- |
| 留资 | `public.js`（`createLead` 的租户守卫 `:612`） | 现在提交需求会不会落成一张真订单 |
| 客服 | `chat.js:202` `resolveVisibleListing()` | 现在开线程/追加消息会不会被 409 |
| 个人页收藏卡 | `buyer-auth.js`（M7 的收藏读） | 这颗心点下去是详情页还是 404 |
| 卖家公域表现 | `analytics.js` | 「能不能被看到」这一列 |
| 投影修复与降权扫描 | `snapshot.js:332` / `:353` | 哪些行需要被藏、哪些是残留 |

加上 `snapshot.js:68`（`existingSellerSlug()` 里「先看可见行」）与 `:159` / `:288`（折成 `'hidden'`）——同一个「可见」词在整个文件里只有一个判据。

App 必须遵守的推论有三条，每条都在 §6 已经出现过，这里给它们的共同根：

1. **不要把 409 当 bug 报。** 详情页加载成功、提交需求返回 `LISTING_UNAVAILABLE`，是这一句裁决在两个时刻各自成立的结果，中间卖家可能刚暂停了申请。§6.6 已经写了正确处置：读回 `error.code`，提示「该商品当前不可接单」，并保留买家已经填的字段。
2. **不要在 App 里维护「在售」缓存。** 可见性是两个条件的合取，而第二个条件（私有申请行的 `status`）**根本不在任何公域出参里**。想自己判就必须猜，猜错的后果是给人点进 404。
3. **收藏的心不能因为一条下架就消失。** §6.8 写了 `listBuyerFavoriteSlugs`（成员真相读）**故意不做任何可见性判断**——已经握着的心必须保持填充状态。判据在 `listing_visible` 这一个字段上，不在集合里。

### 7.3 金额一律服务端按投影价重算

`createLead()` 的文档块（`public.js:547–557`）里那句「**金额一律服务端按投影表价重算**」是有具体代码形状的：

```js
const unitPrice = Number(listing.price_ukr || 0);        // 来自投影行，不来自请求
const subtotal = (unitPrice * finalQuantity).toFixed(2); // finalQuantity 由服务端按箱/散算
```

请求体里**没有**金额字段可以提交，也没有 `unit_price`。买家提交 `quantity` / `box_count` / `piece_count`，服务端按投影行的 `price_ukr` 与私有商品行的 `units_per_box` 算小计，把小计写进 `mp_leads.quoted_amount`，把**混合均价**（`unit_price = subtotal / finalQuantity`）写进订单明细。§2.3 之所以禁止 App 引入任何「计价」逻辑，最终根据就在这里：**一个会算钱的客户端是一个会算错钱的客户端**。

App 侧唯一被授权的算术是**显示**：`formatPrice(value, symbol)`（`src/api/market.ts:369–384`）做千分位与符号前缀，除此之外不要有第二处把 `price_ukr` 和 `quantity` 相乘的代码。报价确认（「卖家将电话联系」）是业务事实，不是客户端算出来的折扣。

### 7.4 货币符号：一个写入者、一把尺、一个列名的历史包袱

三件事各自都容易写错，合起来是「这一列数字用什么货币记」这一条事实的完整形状：

- **投影列的符号只有一个归一化函数**：`projectedCurrencySymbol()`（`snapshot.js:126`）——trim → 截 8 字符 → 空串折回 `'$'`。它是 `toSnapshot()` 的写入者，也是 `/api/cron` 第 3 档比较漂移用的**同一把尺**（`snapshot.js:146` 的注释说明的正是这件事）。App 读到的 `currency_symbol` 因此永远是**符号本身**，不会是 ISO 码。
- **ISO 码只在一个地方存在，而且宁缺勿假**：`isoCurrencyOf()`（`util.js:182`）返回 `null` 而不是猜一个三字码，所以 JSON-LD 的 `priceCurrency` 是**省略**而不是写错。`displayCurrencySymbol()`（`util.js:212`）是它的反向折法，用于把库里存的 ISO/旧标签折回符号。
- **`price_ukr` 这个列名是历史命名，不是币种断言。** 它是「以租户自己的货币记的价」，`marketplace-currency-v1` 的 COMMENT 已经正名，但没有改名——因为这一列在投影表、排序索引和 API 形状里都出现，改名等于为了一个语义变化去破坏对外契约。

现网读数（2026-10-19 实测）：9 个租户没有一个用 ₴，是 `$×8 / €×1`；而这一列在旧代码里被四个常量硬写（`shapeCard` 的 `currency:'UAH'`、`createLead` 写 `mp_leads.currency`、`formatUah` 的 ₴、`seo.ts` 的 `priceCurrency`），意味着「卖家按美元报价、买家页面全印 ₴」是当时的真实症状。**App 里出现任何一个硬写货币符号的分支，都是在恢复这个病。**

还有一条历史行纪律：已落库的 5 条留资仍带 `'UAH'` 标签，读路径折forward，**不改写**。所以 App 也不要「统一」——`MarketLeadRow.currency` 拿到什么就印什么（§12.4）。

### 7.5 `published_at` 是首次进入公域的时刻，只往前走一次

`firstPublicAt()`（`snapshot.js:177`）是这一条的唯一规则，优先级是「投影现值 → 申请行值 → now」，被三个写公共时钟的地方共用（`:198` / `:200` / `:222` / `:246`）。这决定了 App 界面上「上架于 N 天前」这句话的含义：

- 它是**首次**上架，不是最近一次编辑或重新审核。审核通过不再 bump 它（P2-B 修掉的正是「改一下再提交 = 免费回到最新排序」）。
- 卖家编辑已发布内容会走 CP-3（`content_hash` 变 → 行退回 `draft` → 投影被 `hideSnapshot()` 藏起来），此时 `mp_listings.published_at` 被置空，但**投影行的旧值仍在**——那就是「这条商品曾经进过公域」的唯一存续证据。
- 因此 §6.3 的日历里那一格、和详情页那一行，说的是同一件事、同一把尺（`LISTED_DAY_TIMEZONE = 'Europe/Kyiv'`，`util.js:390`）。

App 侧没有实现义务，只有一条禁令：**不要用「更新时间」冒充「上架时间」。** 投影行有 `updated_at`（每次内容重建都会被 `set_updated_at` 触发器推前），它服务的是 `sitemap.xml` 的 `lastmod`，不是买家看的那个数字。

### 7.6 归因的两列绝不从浏览行为写

这句规则的主语是 `events.js`，不是留资——写反了会造出一个假话，所以两条都要写清：

- `server/marketplace-core/services/events.js:8–15` 的第一条纪律：**`recordMarketEvents()` 从不写 `conversion_stage` / `converted_at`**。原因是这两列喂的是 `idx_mp_attr_pending_upload`，即广告离线回传队列；把浏览行为填进去等于把每一个未转化的会话都推去上传给 Google。
- 唯一从公域路径写这两列的地方是 `createLead()` 的尾部（`public.js:727–733`），且带 `.is('converted_at', null)` 守卫——留资是**转化**，不是行为。所以「公域路径从不碰 conversion_stage」是错的，「埋点从不碰」是对的。

对 App 的含义落在 §6.9：埋点上报的请求体里**没有**、也不该有「这是一次转化」这类字段。App 能写的终态事实只有一件：提交需求（`POST /api/market/leads`），服务端自己把 `lead_form_submit` 事件和归因推进分开处理。

顺带一条同样容易被「顺手统一」破坏的分工：`mp_events` 与 `mp_attributions` 是**两张表，故意不重叠**。`mp_events` 没有 `tenant_id`、没有 `buyer_account_id`（M1 的 DDL 决议：身份不进行为流，这样一次 prefetch/salvage 曝光不可能被重新归属到某个人），`mp_attributions` 没有事件类型。App 只要把这两条 POST 分开发，就自然维持了这个形状。

### 7.7 买家号码只有一个出口形状：`maskPhone()`

`util.js:744` 的 `maskPhone()` 是**唯一**一个「一个买家手机号对外长什么样」的实现。历史上它被抄过三份：`public.js` 的留资回显、卖家留资列表、后台买家面各自在调用点拼 `slice(0,3)+'****'+slice(-2)`。分叉的后果是「这条渠道到底漏了多少 PII」变成无法回答的问题，所以规则是：**新出参加入时调用它，不要在调用点重拼。**

App 侧要守的三条推论：

1. 成功屏上那个号码是 `contact_masked`（§6.6 出参），**不是**买家刚输入的那串。想回显原文只能来自输入框自己的 state，页面重建之后就没有了——这是设计，不是缺陷。
2. 注册/登录之后，`shapeAccount()` 给的 `phone_masked` 是**掩码过的值**，而 `normalizePhone()`（`util.js:69`，剥非数字后要求 6–20 位）在设计上就会拒绝它。所以「用我保存的号码」**是一个意图字段（`use_saved_contact: true`），不是一个可以预填的值**（§6.6 已展开）。
3. 号码**永远不进 URL、不进埋点、不进日志、不进崩溃上报**。`MP_PII_PEPPER` 只作用于 `hashPhone()`（`util.js:734`），而本地没有 pepper 时 `util.js` 会退化并告警——这意味着**本地算出来的 hash 不是现网可对账的值**，任何「我算过号码一样」的自测都不算证据。

补一条常被误当作功能 missing 的：这个系统**没有任何按号码搜索**的入口（公域没有，后台买家面也故意没有——那会把控制台变成 PII 预言机）。App 里不要预留这个口子。

### 7.8 失败读数永不印成结论

这是本项目在 §11 之外被记录次数最多的病根，也是公域端出参里那些 `null` 的全部理由。三条已经写进契约的形状，App 必须原样承接：

| 出参 | `null` 的意思 | 把它折成 0/空 的后果 |
| --- | --- | --- |
| `seller.listing_count`（`public.js` 详情出参） | **这一趟读失败了** | 买家读出「这家一条都没上架」，而事实可能是「没取到」 |
| `rating`（`shapeCard` 14 键之一） | 还没有评分 | 印成 `0.0` 是一颗被抹平的空星 |
| `ttfr_hours`（详情页回复时长） | 还没有可测的留资响应 | 印成「0 小时内回复」是替卖家许下一个他没演示过的速度 |

同一个病根在别处的名字：`safeCount()` 曾经用 `head + count` 读数，而**缺表时 PostgREST 返回 `error: null` + `count: null`**，于是坏掉的读被报成自信的 0；`payment_invoices` 被 DROP 之后仍然有几处在数它，症状同样是 0。`getListedDays()` 的 `truncated`（`public.js:334–364`）是这条纪律的第四个实例：那一格是**下界**，不是总数。

App 侧的写法只有一种正确的：**`null` 走「整行隐藏」或「未取到」，`0` 走「真的是零」，两者不能共用一个渲染分支。** §6.4 给过表格，§10 会给验收条目。这一条之所以放在不变量里而不是移动端章节里，是因为它不是一个样式问题——它是「一个屏幕上的数字是不是事实」的问题。

---

## 8. 移动端专属要求

本章只写**在 Web 上不存在、在 App 上必须重新决定**的事。凡是 Web 与 App 同规则的（信封、分页、语言解析、错误码），前面章节已经写完，这里不复述。

八节的顺序就是实现的顺序：先把网络层钉死（8.1、8.7），再把身份落到设备（8.2、8.3、8.4），最后才是屏幕上的东西（8.5、8.6、8.8）。

### 8.1 超时表：按「这一趟要不要写钱」分档

下表是浏览器端的现值（`src/api/buyerAuth.ts`、`src/api/market.ts`），App 应把它们当成**下限**而不是默认值——移动网络的 p95 比桌面宽，超时给短了的症状是「买家点了提交、界面报错、服务端其实已经建成一张单」，那是最贵的一类不一致。

| 调用 | 方法 · 路径 | 浏览器现值 | App 建议 | 理由 |
| --- | --- | --- | --- | --- |
| 目录 / 类目计数 | `GET /catalog` | 通用 30 s | 30 s | 纯读，可重试 |
| 商品列表 | `GET /products` | 通用 30 s | 30 s | 纯读 |
| 上架日历分面 | `GET /listed-days` | 通用 30 s | 30 s | 纯读，且带 `truncated` 下界语义 |
| 商品详情 | `GET /products/:slug` | 通用 30 s | 30 s | 服务端有自己的限流桶（`market:detail`，`api/market.js:204–208`） |
| 店铺页 | `GET /sellers/:slug` | 通用 30 s | 30 s | 纯读 |
| 跟踪配置 | `GET /tracking-config` | 通用 30 s | 30 s | App 侧通常不需要（见 §9.3） |
| 留资下单 | `POST /leads` | **45 s**（`src/api/market.ts:264–274`） | **≥45 s，且绝不自动重试** | 这一趟会 `process_order_v2` 真的建一张卖家订单（§6.2） |
| 发起客服会话 | `POST /chat` | 15 s | 20 s | 写；可能触发 Telegram 通知 |
| 追加消息 | `POST /chat/:token/messages` | 15 s | 20 s | 写 |
| 读取线程 | `GET /chat/:token` | **15 s** | 15 s | 轮询读；比一般读短是故意的，轮询必须快速失败 |
| 注册 / 登录 / 改密 / 注销 | `POST /buyer/*` | 20 s | 20 s | 写；登录含 scrypt 校验 |
| 我的资料 | `GET /buyer/me` | 15 s | 15 s | 读，但每次调用都鉴权 |
| 登出 | `POST /buyer/logout` | 15 s | 15 s | 写，但**本地先行**（见下） |
| 个人页三块 | `GET /buyer/{conversations,leads,favorites}` | 15 s | 15 s | 纯读 |
| 收藏写 / 删 | `POST /buyer/favorites{,/remove}` | 15 s | 15 s | 写，乐观更新（§6.8） |
| 收藏迁移 | `POST /buyer/favorites/migrate` | 通用 | **20 s** | 一次最多 200 条差集 |
| 埋点批量 | `POST /events` | **8 s**（`src/api/market.ts:347–367`） | 8 s + keepalive 语义 | 见 §8.9 的取舍 |
| 归因落地 | `POST /track` | 通用 | **可丢弃** | 失败静默（§6.9） |

三条从库存端 App 直接搬过来的网络层纪律（`api_client.dart` 的同一套），在公域侧一条都不能松：

- **只给 GET 退避重试。** 写一次都不自动重试。留资、建会话、收藏、注册全部是写；`POST /buyer/favorites` 的重复调用会被 `uq_mp_bfav` 判成 `already: true`（`buyer-auth.js` 的幂等分支），所以它是**唯一**一个「重试不会多写一行」的写接口，但这条豁免不构成通用规则。
- **响应体以 `<` 开头 = 网关 HTML，不是数据。** 公域域名前面是 Cloudflare，一次 502 会带着一张漂亮的错误页回来；把它当 JSON 解析得到的错误信息是「格式错误」，而真实原因是上游没答。App 必须把它归到「网络不可用」那一档，让 §8.7 的离线分支接手。
- **`ensureSession` 那一套属于库存端。** 公域买家会话是服务端行、30 天 TTL、没有 refresh token、没有 401 后刷新重试（`apiCall()` 的 401 重试只对租户 Bearer 生效）。App 里如果出现「401 → 刷新 → 重发」，刷新的对象是不存在的，症状是登录态反复掉。

### 8.2 买家会话在设备上的形状

真相在服务端，设备只保管凭证：

- **键名与内容**：`yuanbao.market.buyer.session`，值是 `{token, expires_at}`（`src/api/buyerAuth.ts:20` 起的读写对）。App 侧的等价物是 Keystore / Keychain 里的一条，不是 SharedPreferences 明文——理由不是它等于密码，而是**拿到它就能以这个人身份读写留资、会话、收藏**。
- **读的时候自逐出**：`readSession()` 发现 `expires_at` 已过就删掉本地行并按「未登录」返回；**每一次写都被吞掉异常**。这不是偷懒：隐私模式 / 配额满 / 权限被收走时，写不进是常态，而这个页面**必须退化成「未登录」而不是崩**。§4 的语言解析同一形状（写不进就按没记住处理）是同一个道理的第二处应用。
- **服务端有效期 30 天**（`BUYER_SESSION_DAYS`，`buyer-auth.js:69`），一行一设备。`last_seen_at` 最多每 5 分钟补一次戳（`SESSION_TOUCH_MS`，`buyer-auth.js:86`），所以「`/buyer/me` 每次都鉴权」不等于「每次都写一行」。App 不需要为此做任何事，但要知道：**本地那个 `expires_at` 只是自逐出的提示，真正的判据在服务端**，所以本地显示的剩余天数不能当承诺。
- **登出与注销必须在 `finally` 里清本地行**（`src/api/buyerAuth.ts` 的既有契约）。App 若等服务端成功再清，一次网络抖动就把用户永久留在「看起来还登录」的状态里；而服务端那边会话可能已经被吊销（后台 M8-A 的第四支写），两者迟早分叉。
- **永不与库存端互换。** 公域 App 不应该出现 `bufang.auth`，也不应该出现 `skipAuth: false` 的调用。`buyerHeaders()`（`src/api/buyerAuth.ts:62–65`）是 `X-Buyer-Session` 唯一的构造点，App 里也应当只有一个构造点。

### 8.3 凭证的两个长度：20 与 80

这是本章最容易在联调时撞、且撞完症状最难看的一条。

- **服务端只取前 80 个字符**：`api/market.js:155–157` 对 `X-Buyer-Session` 做 `.trim().slice(0, 80)`。一个被截断的凭证一定鉴权失败，而它失败得**很安静**——401 `BUYER_SESSION_INVALID`，看起来和「过期」一模一样。若 App 的存储层（某些 JSON 序列化、某些 Keychain 包装、或一次「顺手」的 `substring`）把凭证变长了，症状会是「刚登录后一切正常，杀进程重进就掉线」，因为重启时读的是那条被截断的值。**客户端写入前应自己断言长度 ≤ 80，超长就当没有登录，不要发出去。**
- **服务端把「短于 20」当成没带凭证**：`resolveBuyerIdentity()`（`chat.js:231`）的判据是「≥20 字符才算一个可能的真 token」。所以一个被截到 20 以下的值不会报 `BUYER_SESSION_INVALID`，它会走匿名分支——在门开着的生产环境里 401 `BUYER_LOGIN_REQUIRED`，在门关着时**静默变成匿名**。这条的两个后果：① 已登录用户被静默降级成匿名正是 M2 明确禁止的事（它会让 `buyer_account_id` 永远为空，也就是 M3 要显示的那个身份丢了）；② 客户端绝对不能用「长度不对就发出去赌一把」的写法，本地校验失败就按未登录处理。
- **`buyer_token` 是 43 字符 base64url，不要和会话凭证混用。** 会话凭证（客服）与 `buyer_token`（线程寻址）在 Web 上存在两个不同的地方（`yuanbao.market.buyer.session` vs `ChatWidget` 自己的存储）。App 里也必须存两处；把后者当凭证发在 `X-Buyer-Session` 上不会成功，但也不会报一个有用的错。

### 8.4 User-Agent 决定归因里的设备档位

同一个字段名 `device_class` 在服务端有**两把尺**，而 App 只被其中一把影响：

| 位置 | 谁算的 | 值域 | App 后果 |
| --- | --- | --- | --- |
| `POST /track` → `mp_attributions.device_class` | **服务端从 UA 解析**（`buyer-auth.js:106` `deviceClassOf()`） | `mobile` / `desktop` / `null` | UA 里没有 `android` / `iphone` / `ipad` / `pod` ⇒ 归因行记成 `desktop` |
| `POST /events` → `mp_events`（`events.js:147–149`） | **客户端自报** | `mobile` / `desktop` / `tablet` / `null` | App 可以直接报 `tablet`，UA 那把尺不行 |

第一把尺是本章要管的：Flutter / OkHttp / URLSession 的默认 UA 常常是 `okhttp/4.12.0` 或空，`deviceClassOf()` 对它只能答 `null`，而 `null` 在后台归因板上会落进「未知」而不是「移动」。这不会报错，只会让**买量报表里 App 流量的设备档位永远看不见**。要求：

- App 的 HTTP 客户端必须显式设置一个包含平台词的 UA，例如 `TorgSeekMarketApp/1.0 (Android 14; SM-G991B)` 或 `... (iPhone; iOS 18.1; Scale/3.00)`。写成 `Mobile` 字样不够——判据是那几个平台词。
- **不要伪造完整浏览器 UA**。归因不需要它，而它会让 §9.4 的 PII 面（IP 哈希）之外的东西变得不可解释。
- 两把尺这件事本身记在 §11，不在这里假装它只有一把。

### 8.5 图片：只有读，没有上传

公域 API 里**没有任何上传图片的入口**，这不是遗漏而是身份边界：图集属于卖家，写入走 `product-images` 公开桶 + 租户会话（`uploadProductImage()`），资质文档走 `mp-assets` 私有桶 + Storage RLS（`uploadMarketDocument()`），两者都要求调用者是某个租户的成员。买家能做的只有：看别人的图、留电话、发文字。

- **URL 已经是绝对的**：投影里的 `image_urls` 由 `resolvePublicUrl()`（`util.js:782`）解析成完整地址，App 直接用来加载，不要自己拼桶路径或补 `VITE_SUPABASE_URL`。
- **`image_count` 可以是 0**，而且这是一个诚实的值：`projectedImageUrls()`（`snapshot.js` 的 §7 那条）会把非本站域、`data:` 裸块、别人的租户前缀全部滤掉，滤空就是空。所以「无图卡片」是设计里存在的一档（闸 5 在 `mp_image_gate_enabled` 开着时会拒绝它，但历史行仍在），App 必须有对应的占位样式，而不是假设每张卡都有图。
- **`/N` 角标的分母是 `image_count`**，不是数组长度——两者在投影侧应当一致，但 Web 的规则是「读服务端给的数，不自己数」。
- **读侧缓存可以用**（`cached_network_image` 那一类），但要清楚它缓存的是一张**公域页面已经替卖家展示过**的图，不是任何带鉴权的临时签名链接。公域响应里不会出现 `sign` 链接：只有后台审核员拿 180 秒签名 URL（`getDocumentSignedUrl()`），那条路不在这个 App 里。
- **不要规划「买家上传照片」功能**。真需要（比如纠纷举证）的话，那是新的存储桶 + 新的鉴权面 + 新的审核流，属于服务端的一个增量设计，不是 App 的一个页面。

### 8.6 深链、语言、返回：三件在 Web 上互相牵住的事

Web 侧的四个可寻址页面是 `/market`、`/market/p/:slug`、`/market/s/:seller`、`/market/me`；查询参数是 `?lang=`、`?seller=`、`?category=`、`?chat=open`。App 的等价映射与两处必须照抄的行为：

1. **语言必须跨站内跳转存活。** Web 靠 `withLangParam()`（`src/pages/market/nav.ts`）把当前语言带进每一条站内路径，因为商品卡是真的 `<a href>`、点一次就重新加载文档。App 里语言是 store 状态，天然存活——**但落地链接与分享链接仍然要能读 `?lang=`**，因为广告与分享都来自 Web 地址。§5 的解析链（URL → session → 显式选择 → `navigator.languages` 整列表 → `uk`）在 App 里的等价形式是：深链参数 → 上一次显式选择 → 系统语言列表 → `uk`。自动检测的结果**永远不写回偏好**，这条也在 App 里成立，否则第一次猜错就冻成永久。
2. **`?seller=` 是一个 slug，不是店名。** §6.6 的理由在 App 里同样成立：店名是卖家会改的内容，slug 是冻结的地址。买家侧「只看这家」的入口参数只能是 `seller_slug`。
3. **`?chat=open` 是「继续已有线程」，不是「开一个新线程」。**个人页（§6.7）的「继续对话」用 `conversation_token` 恢复既有线程；如果 App 把它实现成「进入商品页就 `POST /chat`」，同一个商品会长出第二条线程，卖家的收件箱被同一个人问两次，而 `mp_conversations.buyer_token` 的 UNIQUE 会让第二次的形状很怪。

**返回按钮**的原生等价物要说清它替代的是什么：Web 用 sessionStorage 键 `yuanbaokucun.market.inapp`（`src/pages/market/nav.ts` 独家读写）记录「上一个文档是站内离开的」，配合本文档自己的 pushState 深度决定返回是回上一页还是回 `/market`。**App 的导航栈就是这个信息的载体**，规则因此变成一句可以照着写的话：栈里有站内上一页就弹栈；没有（付费深链 / 分享链接直接落在详情页）就去 `/market`。**不要为了「记住筛选」而伪造一层历史**——Web 的注释把取舍写得很直白：少一层筛选记忆比把付费点击甩出本站便宜。

### 8.7 陈旧数据：公域侧的离线横幅比库存端更严格

库存端 App 的离线缓存返回 `ApiResponse(stale: true, cachedAt: ...)`，界面挂「可能不是最新」横幅——那条搬过来，但**作用范围要收窄**，因为公域上的数字是买家据以行动的事实：

- **列表、店铺页、日历分面可以 stale 显示**，条件是横幅 + 明确的时间戳。投影的库存列由 `/api/cron` 的 job 3 每小时收敛，价格与店名只在卖家重新提交时变；「一小时前的列表」是一个诚实的历史快照。
- **详情页的价格 / 有货 / 起订量不允许用缓存值去支撑「提交需求」按钮的可点状态。** §7.3 的裁定权在服务端：`createLead()` 会重新读投影行、重算金额、再回查私有申请单与租户状态。所以 App 的正确形状是：**按钮永远可点（只要页面是渲染出来的），提交后按错误码分档解释**（`OUT_OF_STOCK` / `BELOW_MIN_ORDER` / `OVER_STOCK` / `LISTING_UNAVAILABLE` / `TENANT_UNAVAILABLE`，见 §12.2）。用缓存值把按钮灰掉，症状是「明明有货却说无货」，而且买家没有重试入口。
- **语言包 / 类目树可以缓存**（类目是平台资产，变化频率以周计），但**每条计数都是服务端给的**（§6.1 的 `mp_category_listing_counts()` 那条纪律）：类目树缓存 + 现数计数是允许的，缓存整棵带计数的树会造出一个会撒谎的 chip。
- **一次会话读（`GET /chat/:token`）失败时，宁可显示上一次的消息 + 横幅，也不要显示「没有消息」。** §7.8 的同一条：读失败与空集是两个结论。

### 8.8 吸底条、安全区与「一个实例两个入口」

Web 上被两轮实测钉住的两条纪律，在 App 上更容易被写错，因为原生布局系统不会提醒你：

- **任何贴在底部边缘的悬浮元素，它的偏移必须由被测元素自己发布的高度推导，不能用像素常量。** Web 的做法是 `MobileBuyBar` 用 `ResizeObserver` 把 `offsetHeight` 写进 CSS 变量 `--mk-dock-h`，客服面板 / 回到顶部 / 桌面端 FAB 都读它。原因是这一格的高度依赖 `env(safe-area-inset-bottom)`、翻译长度（乌克兰语的按钮比中文长一截）和粗指针设备的字号上浮。App 里对应的写法是：底部操作条把自己的高度上报给页面状态，悬浮层从状态里读；**不要写 `bottom: 76`。**
- **客服只有一个面板实例、一个状态持有者，但有两个入口按钮。** Web 的形状是：商品页持有 `chatOpen` / `chatUnread`，移动端入口在吸底条的右侧按钮组里（`sm` 以下只剩图标 + `aria-label`），桌面端入口在面板自己那颗药丸里；`chat_open` 埋点由面板侧**一次 false→true 边沿**记录，所以「折叠再展开」不会被记成一次打开。App 里最容易犯的错是在两处各自 `useState(open)`——那会长出两个 `buyer_token` 与两个轮询定时器，也就是同一问消息被拉两次、未读点在不同位置各自为真。
- **键盘不能盖住留资表单。** Web 的做法是吸底条的「提交需求」滚动到 `LeadForm` 的根节点（id 是 `market-lead-form`）。App 里等价行为是：点吸底条 → 焦点进到号码 / 需求字段 → 表单滚到键盘上方。注意 §6.2 的「已登录买家不再重填号码」那一档：字段此时是**只读 + 一个「改用其他号码」出口**，键盘弹起不应把它顶出可视区。
- **移动端一切单列**（Web 规则：`grid-cols-1 sm:grid-cols-2 …`，`sm` 以下商品卡是横向封面 118px、卖家说明隐藏）。App 的屏幕宽度大致落在 Web 的 `<sm` 档，所以**参照物应该是 Web 的手机档而不是桌面档**；桌面两列网格在 App 里没有对应形态。

### 8.9 埋点在 App 上的两个不同问题

§6.10 的八类事件与四类上送平台的划分照搬，但 App 上有两件事与浏览器不同，必须各自决定：

- **没有「硬跳转」，所以 keepalive 的原始动机消失了。** Web 之所以在点击时用 `keepalive: true`（`apiCall()` 的该选项会丢掉 AbortSignal 并把超时压到 8 s），是因为商品卡是真的 `<a href>`：点下去文档就卸载，普通 fetch 会被杀死，CTR 的分子悄悄消失。App 里导航不销毁进程，一次普通的异步 POST 就能活到发出去——**但仍然建议把「即将离开当前页面」的事件在导航前 flush**，因为原生实现里也常有页面被回收。规则照抄：队列 20 条或 1.5 s 一flush，点击与页面销毁时立刻 flush。
- **没有 `IntersectionObserver`。** 曝光的分母（40% 可见、`${source}|${view}|${position}|${slug}` 去重、会话内 500 键上限）要用平台的可见性回调重做：Flutter 的 `VisibilityDetector`、SwiftUI 的 `onGeometryChange` 一类。**判据不要改成「渲染即曝光」**——一屏 24 张卡在滚动前全部渲染，那样分母会包含买家根本没看到的行，CTR 被压低，而 CPL 是拿 CTR 的分母算出来的（§7.6），等于平台自己在给自己制造一个偏低的价格。
- `view` 是**客户端去重键**，不是持久判别（§6.10）。App 里可以把它放进内存，但它不会出现在 `mp_events` 的任何一列里。

## 9. 发布与合规

库存端那一章讲的是「怎么把包打出来」，公域端这一章讲的是**另一件事**：这一面是花钱买来的流量落地的地方，它对外承担三项库存端没有的义务——**广告披露、买家个人信息、以及一个不由业主控制的浏览器环境**。构建本身在这一章反而最轻。

### 9.1 构建路线：云端，照库存端那一套

本轮的目标是把 App 打出来，不是把它送进应用商店。所以构建路线**直接复用库存端已验证的两个 GitHub Actions 工作流**（`kucun-app/.github/workflows/build-apk.yml`、`build-ios.yml`），公域端不新增第三套构建形状。三条约束照抄，因为它们解决的是真实故障而不是洁癖：

1. **构建只在 Actions 上跑，不在本机打签名包。** 本机没有 Android SDK / Xcode 的一致环境，一次「本地能过」的构建对下一次部署没有任何证明力。
2. **构建产物是壳，数据仍然来自线上。** 与库存端同一条理由：App 里没有一行业务数据，`https://www.torgseek.com/api/market/*` 换了，重开 App 就是新版。所以**没有升级路径要设计**，也不该写一个暗示需要重新下载的「检查更新」入口。
3. **公网域名与 API 域名是同一个源**——公域走 `www.torgseek.com`（库存端 App 走 `app.torgseek.com`），两个 host 现在都在 Vercel 同一个项目下。`src/config/site.ts` 的 `siteOrigin()` 就是这一面，App 的 `apiBase` 应该拼成 `https://www.torgseek.com/api/market`，**不要**指向 `app.`。这不是风格问题：`/api/market/*` 的同源判据是 `new URL(origin).host === req.headers.host`（见 §9.3），指错 host 时跨域读会被静默拒掉。

**明确押后、本文档不写的四件事**（业主决定：以后真正要上 Google Play / App Store 时再优化）：Firebase 相关配置与 `firestore.*` 那一族文件、图片路径的 token 折叠后缀、FCM 推送。**这四件押后不影响本文档任何一章的成立**，因为它们没有一处被写进「必须」——特别是推送：公域侧本来就**没有任何主动触达买家的服务端通道**（买家消息的新到达只有卖家侧 Telegram，§6.7），App 要做通知只能自己做轮询，那是推送之前的另一件事。

### 9.2 二进制里不许有密钥

这一条在库存端是「API key 不能打包」，在公域端要多说三层，因为公域看着「什么都没锁」，最容易让人以为没有机密。

| 值 | 能不能进 App | 理由 |
| --- | --- | --- |
| `yb_live_…` / `yb_admin_…` 外部 API key | **绝对不能** | 那是服务器对服务器的凭据，`/api/external/v1/*` 明写**没有浏览器 CORS**。打包进一个可被反编译的分发物等于把租户的整库读写公开。 |
| `SGTM_SHARED_SECRET` | **绝对不能** | 它是 `POST /track` 那条非同源落地路径的服务端旁路（§6.9）。放进 App 就是让任何人都能伪造归因行。 |
| `VITE_SUPABASE_URL` / anon key | 技术上可以，但**公域端不需要** | 库存端用它做认证；公域买家的会话是服务端签发的 `X-Buyer-Session`，与 Supabase Auth **完全无关**（`api/market.js:155–157` 那句「绝不看 `Authorization`」）。把 anon key 打进公域 App 只会诱导有人去直连 Supabase 读数据——那正是 §7.1 禁止的事。 |
| 广告平台 ID（GTag / Pixel / TikTok） | **不作为构建机密存在** | 它从 `GET /api/market/tracking-config` 公开读回来（§9.5）。填哪一家的 ID 哪一家才生效，换 ID 不需要重新打包。 |
| 买家会话令牌 / `buyer_token` | 只存在于**运行时**的加密存储 | §8.2、§8.3。 |

### 9.3 CORS、WebView 与「只有三个动词」

`api/market.js:68` 的注释原文是：**「同源之外，`APP_CORS_ORIGINS`（逗号分隔）列出的源可跨域读公域集市——给 App WebView / 落地页用；缺省保持仅同源」**。这一句是 App 侧唯一被服务端**预先设计过**的跨域口子，因此它同时是边界，不是邀请。四条必须照读的实现约束：

- **原生 App 的 HTTP 客户端通常根本不发 `Origin`**（没有浏览器同源策略），所以 §8 全章的调用在原生网络层**不需要**任何 CORS 配置。`APP_CORS_ORIGINS` 只对 **WebView** 有意义——也就是说，如果这一面要用 WebView 内嵌 `https://www.torgseek.com/market` 的页面，才需要把宿主源加进那串环境变量；纯原生请求不要为了「保险」去加它。加宽它等于给整个公域集市（含留资、会话、收藏三条买家路径）开出一个新的可读源，而那是业主的一次独立决定。
- **`Access-Control-Allow-Methods: GET, POST, OPTIONS`**（`api/market.js:85`）。这里**没有 PUT / PATCH / DELETE**。前端因此早就按这个形状写了：移除收藏是 `POST /market/buyer/favorites/remove`（`src/api/buyerAuth.ts:258–260` 把这条理由写在注释里）。App 里请**沿用同一批动词**——服务端没有 DELETE 路由，写成 DELETE 会得到 404 `NOT_FOUND`（`api/market.js:371` 的兜底），而不是「方法不允许」。
- **`Access-Control-Allow-Headers: Content-Type, X-Request-Id, X-Sgtm-Token, X-Buyer-Session`**（`:86`）。只有这四个头能过。App 若自己加一个 `X-App-Version` 之类，在 WebView 下会被预检拒掉；要带版本信息就放进 body 或 UA（§8.4 已经说明 UA 另有用途）。
- **同源判据是 host 相等，且脏值一律不算同源**：`sameHost()`（`:90–96`）里 `new URL(value)` 抛错就返回 `false`，注释写「绝不把脏值当成「同源」」。这决定了 §9.1 第 3 条——`apiBase` 拼错 host 时的失败是**安静的**（`Access-Control-Allow-Origin` 干脆不下发），症状是「WebView 里数据全空」，不是报错。

**CSP 的 `script-src` 自 2026-10-14 起没有 `'unsafe-inline'`**（只剩 `'self' https://cdn.paddle.com`）。这一条只对 WebView 生效，但生效方式很坑：**内联脚本不执行且没有可见错误**，库存端那一轮为了这个把打印窗口的三种内联形态全部搬出去了。所以 App 内嵌任何 HTML 时，**不得写内联 `<script>`、不得写 `onclick="…"`**，一切脚本走外部文件。

### 9.4 个人信息与同意：公域端有四个字面证据

库存端的个人信息是「租户自己的客户」，权责清晰；公域端的个人信息是**陌生人留下的**，所以每一处都要能回答「他同意了什么」。代码里已有四个落点，App 必须继续写它们，而不是重新发明一套同意模型：

| 字段 | 写在哪 | 读得到什么 |
| --- | --- | --- |
| `consent_marketing` | `public.js:485`（`mp_buyers` 侧）与 `:639`（留资侧）；`buyer-auth.js` 账号侧 | 出参只有布尔，回读见 `:491` 的二次 select |
| `consent_at` | `public.js:486` | 只在勾选为真时写时间戳，未勾选写 `null`——「同意」与「同意时间」是同一支写 |
| `accepted_terms_at` | `buyer-auth.js` 的 `ACCOUNT_COLUMNS`（`:96`） | 注册那一刻的时间 |
| `phone_e164` | 服务端行内明文 | **出参永远是 `maskPhone()` 的产物**（§7.7），注销时被 NULL 掉 |

三句要实现的规矩：

1. **营销同意默认关闭是库里的形状**：`database-migration.sql:1365` 与 `:1597` 两处都写 `consent_marketing BOOLEAN NOT NULL DEFAULT FALSE`。所以 App 的复选框**默认不勾**，而且不能因为「本地存过 true」就替买家勾上——一次勾选是一次写入，不是一个偏好。
2. **号码永远不进 URL、不进埋点、不进日志、不进崩溃上报**（§7.7 的重申）。App 的崩溃采集器会默认带上最近的 URL 与自定义键，这一面的上报白名单必须显式排除这些。
3. **注销入口必须是显式的**。`closeBuyerAccount()` 是墓碑不是删除（§6.2），App 里给一个「注销账号」按钮并说清后果，这件事在 iOS 上是上架硬要求。本轮不上架，但入口的形状现在就定，不要等到提交商店时临时补一个只清空本地状态的假注销。

`mp_events` 只有 `ip_hash`，没有明文 IP、UA、token；埋点通道也不接受任何买家标识。App 不需要「匿名化」什么，它需要的是**别把新东西塞进去**。

### 9.5 广告披露：这一面是买来的流量

公域首页与卡片是付费点击的落地处，因此有一条库存端完全没有的义务：**付了钱的展示要被认出来是付了钱的展示**。

- 「推广」标注的判据是 `is_promoted`，服务端在 `listProducts()` 那一层由 `isPaidSlotPool(row.pool)` 派生（`public.js:294–303`）。**显式排序不摘掉这个标注**——按价格筛的结果里那一格这一小时确实卖出去了。App 不要把「推广」标签做成「只在推荐流显示」，那是把它降级成装饰。
- App 侧目前**无法**执行平台转化回传。`src/pages/market/tracking.ts` 注入的是浏览器 SDK（`gtag` / `fbq` / `ttq`），原生环境里没有这三个全局对象。这不是遗漏，是一个**未决架构决定**：要么用 WebView 承接落地（代价是 §9.3 那一整条 CORS/CSP 面），要么补服务端 CAPI 那一档（AGENTS.md 记为投放跟踪的第二阶段，凭据填进来之前不写）。本文档不假装它已经解决，§11 里是一条明写的未决项。
- 现在能确定的是：自家埋点（`POST /market/events`）在 App 上照常工作，它是**平台自己的度量**，与广告平台回传是两条独立的路。§8.9 的曝光判据纪律就是为它写的。

### 9.6 四语与本地化：公域的解析链和库存端不是一个东西

`MARKET_LANGS = ['uk', 'en', 'zh', 'vi']`，兜底档是 **`uk`**（`MARKET_FALLBACK_LANG`）。这一面的解析链自己走一遍：

```
URL ?lang=  →  sessionStorage（本标签上一次解析结果）  →  localStorage（仅显式切换写）  →  navigator.languages 整条列表  →  uk
```

四条与库存端**不同**的地方，实现时必须分开对待：

1. **它是独立的实现，不是共享 store。** 库存端读 `yuanbao.lang`，公域读写 `yuanbao.market.lang` 与 `yuanbao.market.lang.session`（§12.5），两边**永不互读**。理由写在设计记录里：付费点击 aimed at 乌克兰买家，不能让卖家自己的控制台偏好决定买家看到什么语言。
2. **`navigator.languages` 要扫整条列表，不是第一条。** 乌克兰 Windows 常见显示语言是 `en-US` 而 `languages: [uk, en, ru]`——只读第一条会答成 English。这一条在库存端刚刚造成过一次「首屏闪中文」的修复（提交 `f682e14`），公域侧已经同形。
3. **自动检测结果永远不写回偏好。** 只有 `LangSwitch` 上的一次显式点击才写 localStorage，否则第一次猜测会被冻成一个人的偏好。
4. **文案包是自成一包**（`src/pages/market/copy.ts`，四语齐全，不复用控制台的 `*_extra` 包）。App 直接搬这个文件，不要接进库存端的 i18n chain。

**长句在窄屏上的裁切**：乌克兰语最长。Web 侧已实测过同一档三语在 320 / 360 / 390 / 430 / 640 / 768 px × 根字号 15 / 16px 下的表现，结论值得直接引用为验收判据：**留资按钮保持完整标签，客服入口收缩为图标（`aria-label` 承载名字）**，≤390px 时先让步的是次级元信息行（「有货 · 起订 N」在 uk/360 会截断）。App 里遇到装不下的时候，**削的是次要信息，不是主 CTA 的名字**，并且**不允许**靠缩小 `min-w` 来「腾出」空间——库存端记录过一次：搜索框与分段控件同行会留 97px 正文，而占位符在 zh/en/uk 需要 173/199/242px，每一语都会截。

## 10. 验收清单

这一章不是功能清单，是**判据清单**。每一条都必须能被一次操作 + 一次读数判真假，并且写清了「读什么」。凡是只能靠"看起来对"来确认的条目，一律不写进这里——它们要么进 §11 作为未验证项，要么根本不该被声明。

用法：每一个阶段（读路径打通、买家账号打通、留资打通、客服打通、埋点补齐）结束时，把该阶段涉及的组整组跑一遍。**判据全部是"服务端说什么"，不是"界面显示什么"**；界面只是服务端出参的一种渲染，用它验收等于用自己的实现验收自己的实现。

---

### 10.1 身份与会话

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 未登录状态可以浏览列表、详情、店铺页，全程**不出现任何登录提示阻塞** | 冷启动、清除本地存储后直接进 `/market` 等价路径 |
| 2 | 注册成功后本地只写入两个东西：买家会话令牌与 `buyer_token` 类凭证，**没有**任何 `Authorization`、任何 API key、任何 Supabase 会话 | 转储设备上的加密存储，逐键点名 |
| 3 | 注册与登录请求的 header 里**没有** `Authorization`；服务端凭 `X-Buyer-Session` 认人 | 抓一次包，看请求头集合 |
| 4 | 会话令牌跨 30 天后自逐出：读到一个已过期的本地条目时，客户端把它删掉并按"未登录"渲染，**不发**一次注定 401 的请求 | 把本地 `expires_at` 手动改到过去，冷启动 |
| 5 | `GET /api/market/buyer/me` 返回的字段集合与 `shapeAccount()` 的白名单逐字一致：**没有** `password_hash`、`phone_e164`、`phone_hash`、`session_token` | 打日志把出参键集合打印出来，与 `buyer-auth.js:96` 的 `ACCOUNT_COLUMNS` 对账 |
| 6 | 登录连续失败 5 次后拿到 429 `BUYER_LOGIN_LOCKED` + `retry_after_seconds`，客户端倒计时而不是再试 | 用错密码打五次 |
| 7 | 注销走的是服务端 `POST /buyer/close`，成功后本地在 `finally` 里清空；**清空本地不等于注销** | 注销后用第二个设备登录同一号码，账号应已是墓碑 |
| 8 | 买家会话与库存端会话永不互读：登录公域买家后，库存端的 `bufang.auth` 不发生任何变化（在同一个 WebView 里尤其要验） | 两个凭证的读写点各自单独跑一遍 |

**这一组的失败症状长什么样**：4 号没做，用户每次冷启动多一次 401 且界面闪一下"请重新登录"；7 号做假了，用户以为删了号，实际号码还在库里。

---

### 10.2 列表读路径与谓词一致性

这一组是整个公域端**最容易被做假**的一组，因为"能列出商品"和"列出的正是买家在网页上会看到的同一批"是两个完全不同的结论。

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 默认档（不传 `sort`）返回的 `pool` **不含 `muted`**；显式传 `price_asc` / `price_desc` / `newest` / `stock` 时同一批数据里 `muted` 的行**必须出现** | 出参里 `pool` 不外泄（`shapeCard()` 白名单里没有它），所以这一条要**直接读 `/api/market/products` 的原始 JSON 长度**与网页同一档对比条数，而不是看卡片 |
| 2 | 同一条目、同一页、同一排序下，App 列表的第 N 个 slug 与浏览器 `/market` 的第 N 个 slug 逐个相等 | 两边各打一次有序 slug 列表并排比对 |
| 3 | 卡片键集合等于 `shapeCard()` 的 14 个白名单键，**不多不少** | 把一行的键集打印出来与 `public.js:106–131` 对账 |
| 4 | 出参里读不到 `pool`、`rank_score`、`ctr_7d`、`tenant_id`、`listing_id` | 递归扫一遍响应找这五个键名 |
| 5 | `is_promoted` 为 true 的行，卡片上必须有推广标注；**切到显式排序后标注仍然在** | 2026-10-30 重读：`ad_enabled` 已开，但现网仍测不出 `true`（唯一的计划是 `canceled`、零 `paid_boost` 行）⇒ 这一条**仍然**只能用构造的本地假数据验渲染分支，并在验收记录里写明那不是现网读数。见 §11.1 A1 |
| 6 | 关键词搜索用的是服务端 `search_tsv`（`config: 'simple'`, `type: 'plain'`），App **不做**任何本地二次过滤 | 故意搜一个带 `& | ! ( )` 的字符串：服务端不会 500，App 也不该吞掉它 |
| 7 | `seller` 参数传的是 **slug**，不是店名；传店名返回空集合而不是报错 | 拿一个真实店名去筛 |
| 8 | 未知类目 slug 返回**完整信封**（`items: []` + `total`/`page`/`page_size`），不是错误、不是缺字段 | 随编一个 slug |
| 9 | 分页越界（`page` 超出）时，服务端回落到第 1 页并**如实返回 `page: 1`**，客户端必须采纳返回值渲染，不能继续显示"第 5 页" | `runPagedQuery()` 的兜底分支；把 `page` 打到 999 |

**5 号是唯一一条今天无法在现网跑绿的**，所以它写在这里是作为**渲染分支的判据**（拿到 true 时界面必须怎么画），而不是作为"平台当前在卖广告位"的断言。§11 有对应条目。

---

### 10.3 详情页

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | `GET /api/market/products/:slug` 命中不到时是 **404 `LISTING_NOT_FOUND`**，App 的错误页必须按这个码分档，不是笼统"加载失败" | 编一个 slug |
| 2 | 详情页出参包含 `chat_enabled` 与 `buyer_gate_enabled` 两个布尔位，来自同一次 `marketPublicFlags()` 读 | 键集合对账 |
| 3 | 价格行显示的货币符号取自**出参 `currency_symbol`**，App 里没有第二个硬编码符号 | 全局搜代码里的 `₴` / `$` / `formatPrice` 调用点 |
| 4 | `image_count === 0` 时图集区域**整块隐藏**或显示"暂无图片"，不显示一个空轮播；`image_count > 1` 时 `/N` 的分母是这个字段 | 找一条无图商品（现网有） |
| 5 | `ttfr_hours` 为 `null` 时**整行消失**，不显示"0 小时内回复" | 现网多数行为 null，这一条今天就能测 |
| 6 | `listing.seller` 对象里的名字与网页详情页卖家卡的名字**逐字相等**，App 不使用 `tenants.name` 之类私有字段（出参里也没有） | 同一条商品双端对比 |
| 7 | 相关推荐（`related[]`）为空时不留空白容器 | 构造/找一条孤立类目的商品 |
| 8 | 详情读失败与"这条已下架"是两屏：前者可重试，后者不可 | 断网 vs 撤回一条投放（后者今天测不到，见 §11） |

---

### 10.4 店铺页与供应商筛选

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | `GET /api/market/sellers/:slug` 未知 slug 返回 **404 `SELLER_NOT_FOUND`**，不是空店铺页 | 编一个 slug |
| 2 | **默认流 ≠ 店铺页**：同一卖家，`recommended` 筛出的条数可以少于店铺页条数，两者都是对的，App 不能把其中一个当另一个的缓存 | 这一条是本项目**真实踩过**的：验收台断言两者相等时现网答 `1 vs 2`。App 侧的判据是"两个页面各读各的端点，不共享缓存键" |
| 3 | 从店铺页跳"用价格与支付条件筛这家"时，携带的是 `/market?seller=<slug>` 且 `?lang=` 不丢 | 检查落地 URL 的查询串 |
| 4 | 详情页卖家卡进店链接用 slug，不用店名拼 URL（店名可含中文，`slugify()` 会丢掉非拉丁字符） | 找一条店名为中文的租户 |

---

### 10.5 留资（钱的路径）

这一组的性质与其它组不同：**它是一次真实的业务写入**，会在卖家 `orders` 里生成一张真单。所以它的验收必须在测试租户/测试商品上做，且验收后如实记下一条真留资。

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 提交的成功响应包含 `lead_id` / `order_number` / `seller_name` / `quoted_amount` / `currency` / `quantity` / `contact_masked` / `next_step`，**没有**明文号码 | `public.js:735–757` |
| 2 | 成功后展示的订单号是服务端回查出来的真实 `order_number`，不是本地生成 | 与卖家后台 `orders` 列表对账 |
| 3 | 客户端**不发送**金额、单价、数量之外的价格字段；`quoted_amount` 由服务端按投影表价重算 | 抓请求体，确认没有 `unit_price` / `subtotal` |
| 4 | 起订量不足 / 库存不足 / 已售罄分别拿到 `BELOW_MIN_ORDER` / `OVER_STOCK` / `OUT_OF_STOCK`，三档文案不同、三档都可重试（改了数量之后） | 用一条 `min_order_qty > 1` 的商品构造 |
| 5 | 商品已撤出公域时是 **409 `LISTING_UNAVAILABLE`**，文案是"该商品当前不可询价"，**不是**"提交失败" | 需要一条 `hidden` 投影（现网有一条 `paused` 的，今天可测） |
| 6 | 已登录买家走"用我的号码"时，请求体只带 `use_saved_contact: true`，**不带任何号码字节**；出参仍是掩码 | 抓请求体逐字节 |
| 7 | 会话已失效的登录买家提交时，拿到的是 401 系列的"请重新登录"，**不是**"请输入有效手机号" | 手动把本地会话改成过期再提交 |
| 8 | 提交按钮**永远可点**；状态判定来自响应错误码，不来自本地对价格/库存字段的推断 | 代码审查 + 断网重试各一次 |

---

### 10.6 客服会话

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 登录门开着（**现网即为开着**）时，未登录点"在线咨询"必须被引导去登录，而不是发出一条注定 401 的消息 | 冷启动直接点客服 |
| 2 | 一个 `buyer_token` 只对应一条线程；从个人页"继续对话"进来时**不新开**第二条 | 检查 `?chat=open` 分支复用线程 |
| 3 | 轮询读 15 s 超时（§8.1），失败快速降级为"上次同步于 …"，**不阻塞**界面 | 断网打开会话 |
| 4 | 发送 2000 字以内成功，超长被拒并有明确文案（`MAX_MESSAGE_LEN`） | 打一段超长 |
| 5 | 含禁售词的消息被 `assertNoBannedTerm()` 拒掉（422 系），文案不得暗示"系统检测到违禁词"这类诊断细节 | 用后台禁售词表里的一条 |
| 6 | 买家侧出参里的"谁发的"只有四种状态（verified / anonymous / closed / unknown），App 渲染分支必须能容纳四种且**不合并 unknown 与 anonymous** | `chat.js:104–109`；unknown 是"读失败"，不是"没登录" |
| 7 | 卖家回复在买家侧显示为 `sender='seller'`，系统消息（如线程被关闭）为 `sender='system'` 且本地化文案由服务端下发 | 打开一条已关闭线程 |

---

### 10.7 买家个人页（留资 / 会话 / 收藏）

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 三块各自的 `total` 与列表条数**自洽**，且不借用 `/buyer/me` 的任何计数 | 每块单独读一次并打印 `total` 与 `items.length` |
| 2 | 收藏的**成员真相在服务端**：清空本地存储后重新登录，收藏原样回来 | 这是 M7 的两条硬证明之一，App 侧等价可做 |
| 3 | 已收藏但已下架的条目**仍然出现在列表里**，只是没有可点链接（`listing_visible: false`）；心形按钮不消失 | `removeBuyerFavorite` 不受可见性门控，这条是设计而非遗漏 |
| 4 | 收藏满 200 时是 `409 FAVORITES_FULL`，文案如实说"收藏已满"，不是"操作失败" | 今天难测（需 200 条），列为**未观测分支**进 §11 |
| 5 | 迁移只上传**差集**，迁移成功记一次"已交过的 slug"；重复登录不重复上传 | 抓两次登录的请求体 |
| 6 | 留资列表通过 `buyer_id` 指针取，**出参里没有 `contact_phone`**；已注销账号读留资返回空信封而不是 500 | `listBuyerLeads` 的 `!account.buyer_id` 分支 |
| 7 | 个人页的会话出参带 `conversation_token`，App 用它续线程；出参里**没有** `tenant_id` / `listing_id` / `seller_unread` | 键集合对账 |
| 8 | 这一整页不预渲染、不被索引（web 侧 `noindex,nofollow`）；App 侧对应的是**不要把这一页的任何内容写进共享缓存或系统级搜索索引** | 检查是否有把个人页数据放进可被系统索引的明文缓存 |

---

### 10.8 埋点与归因

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 事件类型只有 8 种，App 不新增词表外的值 | `events.js:24–33` |
| 2 | 一批 ≤ 80 条，客户端队列 20 条或 1.5 s 触发 | `events.js:46` + `analytics.ts` 口径 |
| 3 | **曝光判据是"40% 可见一次"**，用 `VisibilityDetector` 重做，键为 `${source}|${view}|${position}|${slug}`，会话内上限 500 键；**不允许改成"渲染即曝光"** | 这是 §8.9 那条纪律的验收位；判错方向会让 CPL 偏低（§7.6） |
| 4 | 预取（卡片停留 120 ms / 按压 250 ms 触发详情请求）**不发任何事件** | 抓包：预取请求发出时 `/events` 队列不动 |
| 5 | `filter_change` 载荷里带 `seller_slug`（当且仅当 narrowing 到某供应商时），这是埋点里唯一能说明"筛了哪家"的列 | `events.js` 的列白名单 |
| 6 | `device_class` 由 App **自己声明**为 `mobile`/`tablet`，与归因侧服务端从 UA 推导的那一把尺**不是同一支**（§11 有一条专门记这件事） | 两处读数分别打印 |
| 7 | `/track`（归因落地）只在带广告参数时发；`fbc` / `fbp` / `ttclid` 的采集规则在 App 里要么按 web 侧同规则实现，要么明确不发——**不能实现半套** | 见 §11：原生与 web 非同源，这一条是未决项 |
| 8 | 事件里**永远没有**买家标识、号码、`buyer_token`；`ip_hash` 由服务端算，客户端不传 IP 衍生值 | 把一批待发载荷整体打印一次 |

---

### 10.9 语言、货币与长句

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 解析链等价形式：**深链 `?lang=` → 上次显式选择 → 系统语言列表 → uk**；自动检测的结果**永不写回偏好** | 改系统语言，看是否只影响首屏而不落盘 |
| 2 | 扫描的是**整条语言列表**，不是第一个标签（乌克兰语设备的显示语言常是 `en-US`） | 设备语言设为 en、首选语言加 uk |
| 3 | 四语（uk/en/zh/vi）文案包自成一包，与库存端 i18n 链**零耦合** | 检查 App 里没有引入库存端语言 store |
| 4 | 语言切换后所有请求的 `lang` 参数与界面一致，且**不改变服务端读哪一列内容**的判定（vi 读英文列，`readsEnglishContent()`） | 用一条只有 uk 标题的商品，切到 vi 看是否回落到英文列 |
| 5 | 320–430 px 宽度下乌克兰语文案不重叠、不遮挡主 CTA；**留资按钮保留完整标签，客服入口收缩为图标** | 逐宽度截图比对（库存端用 42 个同源 iframe 量过同一形状） |
| 6 | 次级元信息行（有货 / 起订量）允许在 ≤390 px 截断，主价格与主 CTA 不允许 | 同上 |
| 7 | 货币符号来自出参；历史留资行仍标 `UAH` 的行**不在 App 侧被"统一"** | 读一条旧留资 |

---

### 10.10 离线、错误码与限流

| # | 判据 | 读回位置 |
|---|---|---|
| 1 | 只有 GET 退避重试；**写路径永不自动重试**（留资、发消息、加收藏、注册登录全部） | 代码审查：重试分支的谓词必须含"方法是 GET" |
| 2 | 响应体以 `<` 开头按"网关返回了 HTML"处理（§8.1），不尝试 JSON.parse 后把 `undefined` 当业务错误 | 用错误域名或改 hosts 指到网关制造一次 |
| 3 | 详情页的价格 / 有货 / 起订量**不允许用缓存值支撑提交按钮的可点状态**；列表、店铺页、日历可以显示 stale + 横幅 | 断网后分别打开四类页面 |
| 4 | `429 RATE_LIMITED` 有专门的文案与退避（读 `retry_after` 或按指数退避），不当成"网络错误" | 快速刷新列表打满一个桶 |
| 5 | 错误码分档表覆盖 §12.2 全部条目，且"可重试"列与代码里的分支一致 | 逐码对照，缺一个码就是缺一个分支 |
| 6 | 超时值照 §12.1 的最后一列逐端点落地（分组值见 §3.3），重试性照 §12.3，不留一个全局 30 s | 逐端点抓一次耗时上限 |
| 7 | 冷启动时无网络：直接进离线态提示，**不白屏、不卡在加载圈** | 飞行模式冷启动 |

---

## 11. 未验证事项与已知缺陷

> 本章记录**不能写成结论**的事。落地前必须逐条确认。
>
> 两点先说清，因为它们决定这一章怎么用：
>
> ① 前十章描述的是**服务端契约**，每一条都有行号可查；本章列的是「契约在现网**没有被真实行使过**的那一面」，以及「仓库里已经过期但没人改的注释」。前者是**观测缺口**，不是代码缺口；后者是**文字与事实不一致**，代码是对的。两类都不能靠读文档解决，只能靠读回现网。
>
> ② 本章不修改任何既有文件。把过期注释「顺手修掉」会让这一轮的范围从「一份新文档」变成「改动运行中的服务」，那是另一次授权，而且改完之后行号会漂，前十章的引用全部要重走一遍。

### 11.1 未验证事项

| # | 事项 | 现状 | 怎么验证 |
|---|---|---|---|
| A1 | 「推广」标注的渲染分支（§10.2 第 5 行） | **仍未验证，但挡着的原因换了**。原文写的是「`ad_enabled` = `'false'`（业主 2026-10-15 17:27:03Z 关回）」——这一句已被现网推翻：`ad_enabled` 自 **10-28 05:21Z 起为 `'true'`**，`ad_base_lead_price='25'`（10-29 10:47Z）、`ad_slot_cap='15'`（10-29 10:49Z）都已填。真正挡着的是**没有活着的计划**：唯一那行 `ad_campaigns`（`9317d280…`，`kind='cpl'`）10-29 10:50:43Z 建、10:51:31Z 就被取消，`paid_boost` 行数 0，所以 `is_promoted` 仍全为 `false` | 原来那三步已经走完两步半，剩下的不是配置而是业务动作：**一个 `status='active'` 的 CPL 计划 + 一笔真充进来的余额**（`wallet_accounts` 仍 0 行）。等一轮 `/api/cron` 之后读 `GET /api/market/products?sort=recommended`，出参出现 `is_promoted: true` 才算过。在那之前只能用**自己构造的本地假数据**验渲染，并在验收记录里写明那不是现网读数 |
| A2 | 详情页「读失败」与「已下架」两块屏（§10.3 第 8 行） | **未验证**。下架分支要有卖家的撤回动作才有；现网 4 条申请里唯一不在售的那条是 `paused` 而不是 `archived`，用它测「已下架」会测到一个半对的状态 | 「读失败」用飞行模式或本地代理返回 502 造；「已下架」在**测试租户**点「撤回」再打开详情，读回 `404 LISTING_NOT_FOUND` 而不是「暂时无法加载」——两条错误态必须落在不同的屏幕上 |
| A3 | 收藏上限 `FAVORITES_FULL`（§10.7 第 4 行） | **未验证**。现网收藏接近 0 条，而 200 是代码常量 `BUYER_FAVORITES_MAX`（`server/marketplace-core/services/buyer-auth.js`），不是库约束，不会被数据自然触发 | 用验收账号写满 200 条（这属于**现网写**，单独授权），第 201 次读回 `409 FAVORITES_FULL`，且界面文案是「收藏已满」而不是通用「操作失败」。测完按收集到的 id 定点删除 |
| A4 | 原生 App 要不要发 `/api/market/track`（§10.8 第 7 行） | **未决架构决定**，不是待办。`mp_attributions` 的 `fbc` / `fbp` / `ttclid` 三列采集规则在 `src/pages/market/nav.ts`，靠落地 URL 上的 `fbclid` / `gclid` 与 `_fbp` cookie；原生 App 两样都不天然存在，且 App 与 `www.torgseek.com` 不同源 | 先把方向定下来，二选一：① 用 WebView 承接广告落地 = 重新过一遍 §9.3 整条 CORS / CSP 面；② 明确「App 归因只带 `utm_*`，那三列一律不发」。做半套会让后台归因板多出一个「看着像 web 会话但不是」的来源，而那一种来源最难解释 |
| A5 | App 侧的平台转化回传（§9.5） | **不存在，而且服务端没有替代品**。`src/pages/market/tracking.ts` 注入的是 `gtag` / `fbq` / `ttq` 三个浏览器全局，原生环境没有；第二阶段的服务端回传 worker（消费 `idx_mp_attr_pending_upload` 队列）在凭据真的填进来之前不写 | 这一条只能业主决定，不是能「验证」的技术项。但风险要说清：不做，则从 App 发生的留资在 Google / Meta / TikTok 侧永远是「点了广告、没有转化」，广告平台会按这个读数优化，越优化越不准 |
| A6 | `device_class` 的两把尺（§8.4） | **已确认是两把尺，不是缺陷**。埋点侧是客户端自报（`services/events.js:147`–`149`，词表含 mobile、desktop、tablet）；归因与账号侧是服务端从 UA 推导（`services/buyer-auth.js:106`，只有 mobile 与 desktop）。两边都允许为 `null`，含义是「没说清」 | App 在埋点请求体里用 `MediaQuery` 显式写 mobile 或 tablet，**不靠 UA**；同一个测试账号两列允许不同，这是设计而不是 bug。反过来，如果实现里出现「为了让两边对齐而在 UA 里塞 `Mobile` 字样」，判失败 |
| A7 | `mp_events.slot_kind` 的写入半边 | **半验证**：`organic` 那一支已经在现网真写过，`paid` 那一支仍然从未。2026-10-30 读数：`slot_kind` 共 **17 行 `'organic'`**（首行 10-28 11:41:56Z，即开闸之后），其余 **1561 行是 `NULL`** —— 那些是这一列存在之前出生的历史事件。原文那句「值从未写过」与「738 行」都已被现网推进 | 「`NULL` ≠ `organic`」这条纪律因此同时有了两批真实样本，App 侧结论不变：**永远不发这一列**（§7.6）。要看 `paid` 那一支，仍需等一个 `active` 计划 + 一轮 `/api/cron`；在那之前任何「付费位 CTR vs 自然位 CTR」的对比都只能说明「这一列还没数」，不能说明任何行为差异 |
| A8 | `/market/me` 与预渲染、`sitemap.xml` 的刷新时机 | **与 App 无关，但很容易被假设反**。个人页不预渲染、不进 sitemap、出 `robots: noindex,nofollow`；`sitemap.xml` 只在构建时刷新，两次部署之间新上架的商品靠链接被发现而不是靠 sitemap | App 唯一要做的是：别把个人页内容写进共享缓存或系统级索引（Android App Indexing / iOS Web Services）。验证是一次检查——退出登录后，系统搜索里搜不到上一位买家的商品名 |
| A9 | `mp-public` Storage 桶 | **仍未使用**。商品图集走 `product-images`（公开读），资质文档走 `mp-assets`（私有）。App 只按出参 `image_urls` 里的绝对 URL 加载（服务端由 `resolvePublicUrl()` 生成，`util.js:782`） | 确认现状只需读 `sql/marketplace-storage-v1.sql` 的桶清单，再在服务层 grep 有没有写入者，不动现网。App 侧的规则是硬性的：**永远不要自己拼桶名或对象路径** |
| A10 | 本文档没有对任何 App 二进制做过运行验证 | **事实**。文中的行号是对现网仓库的静态核对；「现网读数」来自既有验收台的记录与只读探测，不是这一轮跑出来的 | 唯一的验证方式是按 §10 逐条真机跑。跑不过来的条目（A1–A3、A5）在验收记录里保持「未观测」，**不要**为了让清单好看而改成「通过」 |
| A11 | 公域限流的真实边界 | **未验证**。`server/business-core/rate-limit.js` 是单实例内存 `Map`，Vercel 的并发实例各有一份，所以「多少请求会触发 429」在现网不是稳定的数 | 压测只能证明「会限」，不能证明「阈值」，所以不要把压测出来的数字写进配置。App 要实现的是**一条退避**：读到 `429 RATE_LIMITED` 就退避并提示稍后再试（§10.10 第 4 行），而不是一条「我以为的每秒上限」 |

### 11.2 已知缺陷

**D1 —— `services/events.js:72`–`75` 的注释把 `mp_events.slot_kind` 的状态写成「只合并、尚未落库」，这一句在现网已不成立。**

- 证据：`sql/marketplace-ad-campaign-v1.sql` 已于 2026-10-15 落库并合并进 `database-migration.sql`（PART 2.16.3 的 pool CHECK / PART 2.16.11 的 `slot_kind` 列）；三档验收读数分别是预检 通过 24、事务内彩排 通过 55、落库后 `--go` 通过 37（另有 PostgREST 侧读回 28 通过 · 0 失败 · 0 未跑），schema 六指标实测零漂移。
- **后果（精确版）**：注释里的**规则**仍然正确（`slot_kind IS NULL` 不等于 `organic`），错的是**状态**。如果照状态读，会得出「现在不能提交这个键」，于是 `adEnabled` 那一支被当成永久关闭，付费位与自然位曝光的区分永远长不出来——这是「过期注释被当成现行约束」的教科书形状。
- **新 App 的决定**：以代码为准（`services/events.js:69`–`83`），不改任何既有文件。App **永远不发 `slot_kind`**：这一列由服务端从投影行的 `pool` 推出（`slotKindOf()`，`events.js:84`–`87`），客户端连猜的资格都不该有。
- **2026-10-30 状态更新**：这条缺陷预告的危险已经**被读数排除了**。开闸之后 `events.js` 真的在提交这个键，17 行 `'organic'` 落在库里（首行 10-28 11:41:56Z）——所以「照注释的状态读，会以为这一列还不存在、于是永远不发键」这一支已经走不通了；注释里的**规则**（列的存在性以 `ad_enabled` 作替身、先落库后翻开关）依旧成立，错的仍然只是那句状态。文档按「注释可能落后、读数不会落后」处理。

**D2 —— `src/api/market.ts:110`–`113` 称 `mp_buyer_gate_enabled` 无行；现网自 2026-10-11 16:30:14Z 起是 `'true'`。**

- 证据：那一行由后台 → 系统配置的 `SETTINGS_UPDATE` 审计行写入，70 秒后出现真实买家账号 `f6e92561…` 的注册，即门已经被人走通过。
- **后果（精确版）**：「缺行按关闭」这条**客户端规则没错**，错的是把它当成「现在就是关闭」。照注释实现，界面会按「未登录也可以直接咨询」画出来，落到现网是每次点咨询一个 `401 BUYER_LOGIN_REQUIRED`——症状读起来像「客服入口坏了」，而不是「需要先登录」。更糟的是门判在消息 INSERT **之前**（`chat.js` 的 `resolveBuyerIdentity()` 先于插入，`:259` / `:327` 对 `:335`），被拒那一次不留线程行，所以用户看不到任何「发出去了但失败」的痕迹，只觉得点了没反应。
- **新 App 的决定**：门的开合**只取出参** `buyer_gate_enabled`（`getProductBySlug()` 带，服务端 `marketPublicFlags()` 一次读回，与 `chat_enabled` 同源）。不写「默认关闭」的推断，不做「先让买家打字、失败再提示登录」。

**D3 —— `markLeadStatus()`（`public.js:797`–`817`）的词表里没有 `expired`，而 `mp_leads.status` 在现网可以等于 `expired`。**

- 证据：`expired` 的唯一写入者是 `/api/cron` 第一档（超过 24 小时未处理的 `new` → `expired`），卖家侧接口故意不接受这个值。**2026-10-30 起这一档判过期之前先读反证**：如果这张留资生成的订单已经 `completed`，它不但不会被写成 `expired`，还会当场补上首响时间（规则在 `server/marketplace-core/lead-response.js`）。所以对 App 而言 `expired` 的**含义变干净了**：它现在确实意味着「既没人点、也没发货」，而不是「卖家在订单模块忙，但集市看不见」。
- **后果（精确版）**：这是**故意的**设计——卖家不能自己把还在跟的留资标成过期。但对 App 是真实的分支缺口：买家个人页以及任何展示 `status` 的地方都会遇到一个界面词表之外的值，而「找不到对应标签」在多数实现里退化成空白 chip 或 `Unknown`，那是把「平台已经做过判断」显示成「程序不认识」。
- **新 App 的决定**：状态渲染必须有**默认分支**，且默认分支说事实——`expired` 显示「已过期（平台自动）」，并**不给**任何改状态的入口。App 永远不写这个字段。

**D4 —— `createLead()` 有一处错误消息原样透传、不做翻译。**

- 证据：`process_order_v2` 返回 `success === false` 时直接 `throw new Error(orderResult.message)`，而那句文案写在 SQL 里（`sql/order-stock-message-v1.sql` 把裸 uuid 改成「库存不足：名称 / SKU（需要 N，现有 M）」）。
- **后果（精确版）**：这句话的语言由 SQL 决定，即中文；`t()` 找不到 key 时回落 `zh` 包，所以 uk / en / vi 界面上这一句是中文，**没有任何本地化 hook**。同时它是留资失败里最常见的一条——库存刚好被别人下单吃掉的时候。
- **新 App 的决定**：按 verbatim 显示，**不要**自己拼一句另一种语言的「不够」。拼一次就有两套库存不足算法，而那句里的数字来自 SQL 对 `inventory` 的一次真实读取。App 只做两件事：把它放进明显的错误态，并允许改数量重试（这正是它作为「可重试」一档的意义）。验收记录里如实写「这一句在 uk 界面是中文」。要真正多语言，得改 SQL 文案，那是后端的一次改动。

**D5 —— 原文：「现网 `ad_enabled` 与 `wallet_topup_enabled` 都关着，三张钱包表 0 行，`ad_campaigns` 从未被写过」——2026-10-30 重读，三个断言里错了两个。**

- 证据（改后）：`ad_enabled` 与 `wallet_topup_enabled` 自 **10-28 05:21Z 同为 `'true'`**；`ad_campaigns` 有 **1 行**（`cpl`、`daily_cap_minor=20000`，10-29 10:50:43Z 建、10:51:31Z 取消，`version 0`、`settled_through_at IS NULL`）。仍然成立的是**三张钱包表 0 行**（`wallet_accounts` / `wallet_transactions` 全空，`settle_charged` 每轮为 0）。
- **后果（精确版）**：「推广」标注与 CPL 相关的一切今天在现网**仍不可观测**，但不可观测的原因从「开关关着」换成了「没有活着的计划、也没有余额」。这个差别会直接坑到实现：**「今天看不见」不是「这一支可以省掉」的理由**，而挡住它的那个业务条件（有人建一条不取消的计划并充钱）随时可能消失。反过来，如果照旧文写成「关着」，开闸之后 App 依然不写那一支渲染，缺陷就从数据侧移到了客户端。
- **新 App 的决定（不变）**：把「推广」标注实现成**纯渲染分支**（出参里有 `is_promoted: true` 就画），不实现任何投放状态推断。`is_promoted` 之外的投放字段（坑位发放、剩余预算、坑位数、CPL 构成）**不属于公域买家出参**，它们在 `/api/business/marketplace/campaigns` 那一侧（库存端文档 §6.6）。

这五处缺陷没有一处会让 App 崩，但每一处都会让 App **说出一个不成立的事实**。

---

### 11.3 修订记录（v1.0 → v1.1，2026-10-30）

一次现网只读核查（`scripts/db-status.mjs` + 三支只读探针）把 v1.0 里五处「现网读数」类陈述推翻了。它们全部是**状态**而不是**规则**——规则一条没改，所以本文档的要求与结论一字不动，只把状态翻正：

| # | v1.0 的说法 | 2026-10-30 的读数 | 落在哪一节 |
|---|---|---|---|
| 1 | `ad_enabled = 'false'`（10-15 17:27Z 关回） | `'true'`（10-28 05:21Z 翻开，至今），`ad_base_lead_price='25'`、`ad_slot_cap='15'`（10-29 填） | §11.1 A1、§11.2 D5 |
| 2 | `ad_campaigns` 从未被写过 | 有 1 行：`kind='cpl'`、日预算上限 ₴200，10-29 10:50:43Z 建、10:51:31Z 取消 | §11.2 D5、§12.1 注 |
| 3 | `slot_kind` 值从未写过、全表 `NULL`（738 行） | **17 行 `'organic'`**（首行 10-28 11:41:56Z），1561 行仍是 `NULL`（列存在之前的历史行） | §11.1 A7、§11.2 D1 |
| 4 | 三张钱包表 0 行、`monobank_transactions` 里有非终态 | 三张钱包表仍 0 行（成立）；账单 3 行**全部终态**、非终态 0——第三张（10-28 07:48Z 的 ₴500 充值单）由对账档自己收敛 | §11.2 D5 |
| 5 | `expired` 就是「24 小时没人理」 | 判过期之前先读那张留资生成的订单：已 `completed` 的不但不写 `expired`，还当场补首响时间 | §11.2 D3、§6.4 |

**为什么值得单列一节**：这五条如果留在原处，App 开发者照着实现会犯两类错——把「暂时看不见」实现成「不需要这一支」（第 1–3 条），以及把「平台已经判过」显示成「程序不认识」（第 5 条）。**凡本文档出现「现网恒为 / 从未 / 全为 `NULL`」，都要看它的日期**；日期就是这一节存在的原因。

---

## 12. 附录

### 12.1 `/api/market/*` 完整路由表

> 行号对应 `api/market.js`（2026-10-30 版本），共 **26 条**。CORS 只放行 `GET, POST, OPTIONS`（`api/market.js:85`），**没有 PUT / PATCH / DELETE**——所以「取消收藏」是 `favorites/remove` 而不是 `DELETE favorites/:slug`，这是 App 最容易写错的一条。所有桶都是**每实例内存 Map**，冷启动清零、跨实例不共享（§3.5）。

**公开读（无凭证）**

| 方法 | 路径 | 限流桶 | 定义行 |
|---|---|---|---|
| GET | `/warmup` | `market:warmup` 30/min | :165（真读一行 `mp_listing_public`，不是 head+count） |
| GET | `/catalog` | `market:catalog` 240/min | :175 |
| GET | `/tracking-config` | `market:tracking-config` 240/min | :183 |
| GET | `/products` | `market:products` 240/min | :189 |
| GET | `/listed-days` | `market:listed-days` 240/min | :198 |
| GET | `/products/:slug` | `market:detail` 240/min | :204 |
| GET | `/sellers/:slug` | `market:seller` 240/min | :210 |

**写与客服（凭证可选；门开着则必需）**

| 方法 | 路径 | 限流桶 | 定义行 |
|---|---|---|---|
| POST | `/leads` | `market:leads:<ip>` 8/min + `market:leads:<slug>` 30/min | :216 |
| POST | `/chat` | `market:chat:<ip>` 8/min + `market:chat:<slug>` 30/min | :228 |
| GET | `/chat/:token` | `market:chat:<token>` 60/min | :237 |
| POST | `/chat/:token/messages` | `market:chat:<ip>` 8/min + `market:chat:send:<token>` 20/min | :243 |

**买家账号**

| 方法 | 路径 | 限流桶 | 凭证 | 定义行 |
|---|---|---|---|---|
| POST | `/buyer/register` | `market:buyer-register` 20/min + `…-register-phone:<号>` 5/10min | — | :256 |
| POST | `/buyer/login` | `market:buyer-login` 10/min + `…-login-phone:<号>` 5/15min | — | :265 |
| GET | `/buyer/me` | `market:buyer-me:<token>` 60/min | ✅ | :274 |
| POST | `/buyer/logout` | `market:buyer-logout:<token>` 30/min | ✅ | :280 |
| POST | `/buyer/password` | `market:buyer-change:<token>` 10/min | ✅ | :286 |
| POST | `/buyer/close` | `market:buyer-close:<token>` 5/min | ✅ | :293 |

个人页七条一律走 `buyerAccountBucket()` = `market:buyer-<动作>:<token>`，**60/min**（`api/market.js:141-143`）：

| 方法 | 路径 | 动作桶名 | 定义行 |
|---|---|---|---|
| GET | `/buyer/conversations` | `threads` | :304 |
| GET | `/buyer/leads` | `leads` | :310 |
| GET | `/buyer/favorites` | `favorites` | :316 |
| GET | `/buyer/favorites/slugs` | `favorites`（与上一条共用） | :322 |
| POST | `/buyer/favorites` | `favorite-write` | :329 |
| POST | `/buyer/favorites/remove` | `favorite-write`（三个写入口共用一格） | :336 |
| POST | `/buyer/favorites/migrate` | `favorite-migrate`（整批一次搬，所以单独一格） | :343 |

**埋点与归因**

| 方法 | 路径 | 限流桶 | 定义行 |
|---|---|---|---|
| POST | `/track` | `market:track:<ip>` 600/min；来源不过 ⇒ `403 TRACK_FORBIDDEN` | :351 |
| POST | `/events` | `market:events:<ip>` 120/min，单批 ≤ 80 行 | :362 |

> **两条不属于这张表**：`/api/business/marketplace/*`（卖家的计划、余额、留资收件箱）与 `/api/admin/*`。买家端**永远拿不到**投放的卖家侧数据——这是范围，不是遗漏。

### 12.2 错误码表（按「App 该怎么反应」分组）

> 分支只读 `error.code`，**永不读 `error.message`**（§5.1）。分组标题就是处理策略：同组共用一套 UI 反应，跨组混用会说出假话。

**① 等一下就好（可重试，退避）**

| code | status | 服务端位置 | 意思 |
|---|---|---|---|
| `RATE_LIMITED` | 429 | `api/market.js` 各桶 | 桶撞顶，按 §8.1 退避 |
| `BUYER_LOGIN_LOCKED` | 429 | `buyer-auth.js` 软锁 | 5 次失败 / 15 分钟锁，带 `retry_after_seconds`——这是**账号级**事实，与 IP 级桶不是一回事 |
| `BUYER_SESSION_FAILED` / `BUYER_LOGIN_FAILED` | 500 | `buyer-auth.js` | 服务端这一趟没成，**不改变凭证状态**，可原样重试一次 |
| `DB_ERROR` 等（经 `mapDbError`） | 502 / 404 | 中心映射 | 「没读到」，不是「没有记录」（§7.8） |

**② 输入不对（留在当前屏，标红具体字段）**

| code | status | 意思 |
|---|---|---|
| `INVALID_PHONE` | 400 | 号码折完剩 6–20 位以外（`util.js:72`）。与「会话失效」是两件事，绝不合并 |
| `INVALID_NAME` / `INVALID_PASSWORD` | 400 | 名称为空 / 密码不在长度窗口（`buyer-auth.js:126`） |
| `CHAT_EMPTY` | 400 | 空气泡 |
| `BELOW_MIN_ORDER` | 400 | 低于起订量，**带 `details.min_order_qty`**——用它拼话术，不要自己猜 |
| `OVER_STOCK` | 400 | 数量超过可售（提交前预校验那一档） |

**③ 这一格没了（404，给终点态，不给重试）**

`LISTING_NOT_FOUND`（也用于「缺商品标识」）· `SELLER_NOT_FOUND` · `CHAT_NOT_FOUND` · `LEAD_NOT_FOUND` · `BUYER_ACCOUNT_NOT_FOUND` · `NOT_FOUND`

**④ 现在不行（409 / 403 / 422，可解释，多数不可由用户修复）**

| code | status | 意思 | App 的画法 |
|---|---|---|---|
| `CHAT_DISABLED` | 409 | 客服总开关关着 | 入口本就不该出现（`chat_enabled` 在详情出参里）；真撞上就说「暂不可咨询」 |
| `LISTING_UNAVAILABLE` | 409 | 商品暂不可下单 / 不可咨询 / 不可收藏 | 「已下架」，且不再跳详情（§7.2） |
| `TENANT_UNAVAILABLE` | 409 | 卖家整体不可见 | 「暂不可接单，请联系平台客服」，**不要**说商品有问题 |
| `OUT_OF_STOCK` | 409 | 提交瞬间库存被吃掉 | 允许改数量重试（与 ② 的 `OVER_STOCK` 同源、不同时机） |
| `CHAT_CLOSED` / `CHAT_BLOCKED` | 409 / 403 | 会话已关闭 / 被封禁 | 线程转只读，收起输入框 |
| `FAVORITES_FULL` | 409 | 收藏达上限（带 `details.max`） | 先引导删一条，别静默丢弃 |
| `BUYER_PHONE_REGISTERED` | 409 | 号码已注册 | 直接跳登录，不报「注册失败」 |
| `BUYER_ACCOUNT_CLOSED` | 409 | 对墓碑行做写操作 | 只读；文案不出现「已注销账号」这种称呼 |
| `CHAT_BANNED_WORD` | 422 | 命中平台禁售词 | **保留**用户已输入的文本只标被拒——清空它等于丢劳动 |

**⑤ 凭证问题（唯一一组会影响「登录态」的）**

| code | status | App 必须做的 |
|---|---|---|
| `BUYER_LOGIN_REQUIRED` | 401 | 弹登录/注册；**不清本地会话行**（本来就没有） |
| `BUYER_SESSION_INVALID` | 401 | 凭证不存在或账号已是墓碑 → 清本地键，回匿名可浏览 |
| `BUYER_SESSION_EXPIRED` | 401 | 到期 → 清键 + 一行「重新登录」（§6.8 四态之一） |
| `BUYER_INVALID_CREDENTIALS` | 401 | 号码或密码 / 当前密码不对 → **只标字段**，不叫重新登录 |
| `BUYER_ACCOUNT_SUSPENDED` | 403 | 平台处置过人 → 它自己的一句话，绝不与「已过期」共用分支 |

**⑥ 结构性不可达（出现了就是客户端写错，不是运行时分支）**

`MISSING_SESSION`（`/track` 缺 `session_id`）· `MISSING_BUYER_ACCOUNT` · `INVALID_STATUS`（卖家侧词表，买家端不该发）· `TRACK_FORBIDDEN`（跨站来源）· `CUSTOMER_FAILED` / `PRODUCT_UNAVAILABLE`（500，服务端内部）。

> **一个真实的抄错风险**：`TG_NOT_BOUND`、`MISSING_TENANT`、`TENANT_FORBIDDEN` 也定义在这几个服务文件里（例如 `chat.js:688` 的 `testTelegram`、`:698` 的 `setTelegramNotify`），但那些是**卖家侧**函数，只能从 `/api/business/*` 到达。在公域端错误表里给它们留一行，等于给 App 写一支永远不会执行、也永远不会被测到的代码。

### 12.3 环境变量（全部在服务端；App 侧一个都不许有）

| 变量 | 谁读它 | 缺失 / 配错会怎样 |
|---|---|---|
| `VITE_SUPABASE_URL` | `marketplace-core/util.js`（`resolvePublicUrl()` 与图片主机校验） | 图片路径判定失效：列表能出但封面为空，或被判 `INVALID_IMAGE` |
| `MP_PII_PEPPER` | `util.js` 的 `hashPhone()` / `hashIp()` | **不拒绝写入**，只在模块加载时 `warn` 后退化成裸 SHA-256（号码空间可穷举）。症状是「一切正常」，所以部署清单必须显式核这一条 |
| `SGTM_SHARED_SECRET` | `api/market.js` 的 `trackAuthorized()` | `/track` 只认同源 referer；缺它则服务端来源进不来（App 用不上，见 §6.9） |
| `APP_CORS_ORIGINS` | `api/market.js` 的 `setCorsHeaders` | 只影响**浏览器**。原生 App 不走 CORS，所以「App 一切正常而网页端预检失败」时先查这里 |

**App 侧只允许四个值**：`SUPABASE_URL`、`SUPABASE_ANON_KEY`（公开匿名 key——权限由 RLS 与服务端把关，不靠这串字符保密）、业务 API base、公域站点 base。**绝不允许**：`SUPABASE_SERVICE_ROLE_KEY`、任何 `yb_live_…` / `yb_admin_…`、`MP_PII_PEPPER`、`SGTM_SHARED_SECRET`、以及 Monobank / Checkbox / Paddle / AI 的密钥。已上线的库存端 App（`kucun-app/lib/core/env.dart`）就是按这条收口的，可直接对照。

### 12.4 字段字典（出参键集，以及「可以为 `null` 的键」）

> 记法：`?` = 该键可以为 `null`，而 `null` 与 `0` / `''` 是**不同事实**（§7.8）。键集以服务端出参为准，不在 App 里扩——多一个键就先多一个人猜它从哪来。

**卡片（`shapeCard()`，`public.js:107–133`）** —— 恰好 17 键：`slug` `seller_slug` `seller_name` `title` `sku?` `price_ukr` `currency_symbol` `image_url?` `image_count` `min_order_qty?` `lead_time_days?` `supports_online_pay` `support_uk` `in_stock` `rating?` `published_at` `url`。**`listing_id` / `mp_category_id` / `pool` / `tenant_id` 从不出去。**

**列表（`listProducts()`）** —— `{ items[], page, page_size, total, total_pages, lang, sort, listed }`；`items[i]` = 卡片 **+ `is_promoted`**（只有这一层有，见 §6.2）。`sort` 是**生效档位**的回显（`?sort=` 缺省为 `recommended`），排序 chip 靠它点亮当前项，别在客户端再算一遍。

**详情（`getProductBySlug()`）** —— 卡片键 **+** `description?` `description_en?` `image_urls[]` `spec_attrs{}` `ttfr_hours?` `chat_enabled` `buyer_gate_enabled` `seller{slug,name,support_uk,online_pay,listing_count?}` `category{slug,name_uk,name_en}?` `related[]` `url`。三个 `?` 各有画法，见 §6.4 与 §7.8。

**店铺页（`listSellerProducts()`）** —— `{ seller{slug,name}, items[], page, page_size, total }`。`items` 是**纯卡片，没有 `is_promoted`**——店铺页那一格不是平台卖出去的格子，标了就是虚假披露。

**目录（`getCatalog()`）** —— `{ lang, categories[], total_listings }`；节点 = `id` `parent_id` `slug` `depth` `name` `sort_order` `listing_count`。`name` 是**折好的单字段**（`zh → name_zh`、`uk → name_uk`、`en`/`vi → name_en`，判据 `readsEnglishContent()`，§5.7）——App 不要拿三列自己再判一次语言。

**留资成功回参（`createLead()`）** —— `lead_id` `order_number?` `seller_name` `quoted_amount` `currency` `quantity` `contact_masked` `next_step`。**没有**明文号码、**没有** `tenant_id`。`order_number` 为 `null` 只说明号还没落到（RPC 之后回查），不是失败。

**客服（`buyerChatStart` / `buyerChatGet` / `buyerChatAppend`）** —— start：`{conversation_token, status, seller_name, listing_title, messages[]}`；get 与 append：`{status, seller_name, listing_title, messages[], server_time}`。**一条消息只有四列**（`loadThread()` 的 SELECT 就是 `id,sender,body,created_at`），`sender ∈ buyer|seller|system`。线程里**没有** `tenant_id` / `listing_id`，也没有卖家未读数。

**买家账号（`shapeAccount()`）** —— 恰好 7 键：`name?`（墓碑后为 `null`）`phone_masked` `lang` `country?` `consent_marketing` `created_at` `last_login_at`。注册 / 登录额外回一个 `session_token`（**唯一一次出现**，此后任何接口都不再回它）。`password_hash` / `phone_e164` / `phone_hash` 不在 SELECT 列表里，所以不可能被顺手带出。

**个人页三块** —— 留资 items：`lead_id` `status` `order_number?` `quoted_amount` `currency` `quantity` `seller_name` `seller_slug` `slug?` `listing_title` `listing_visible` `created_at` `responded_at?`；收藏 items：卡片 + `added_at` + `listing_visible`；两者信封都是 `{items,page,page_size,total}`，`total` 是**自己这一块**的、不是全站的（§6.8）。`listing_visible=false` ⇒ **渲染这一行但不给链接**（§7.2 那一个判定的第三个使用者）。

**跟踪配置（`readTrackingConfig()`，`flags.js:173–190`）** —— `{google_tag_id?, meta_pixel_id?, meta_test_event_code?, tiktok_pixel_id?, read_error}`；四个 ID 之外**结构上不可能**带回传凭据。读失败 ⇒ 四个 `null` + 一句 `read_error`，**不是**「平台没配」。

**埋点 / 归因写侧** —— `/events` 回 `{recorded, skipped}`（脏行被跳过而不是整批失败）；`/track` 只回成功与否，不回任何买家字段。App 发错形状的**症状是读数从此不增长**，不是报错——所以这两条必须进集成测试，不能只做联调点检。

### 12.5 与库存端文档的边界（同一平台，两套身份）

共用（不重复写）：§3.2 响应信封、§3.3 超时档位、§5.1 按 `error.code` 分支、语言集合与 `uk` 兜底。

分歧（**混用即缺陷**）：

| 维度 | 公域端（本文档） | 库存端（`inventory-app-development.md`） |
|---|---|---|
| 凭证 | `X-Buyer-Session`（服务端会话行，可吊销） | Supabase Bearer access token |
| 身份主体 | 买家账号（无 email、无 `tenant_id`、不在订阅状态机里） | 租户成员（`users` + `profile.permissions`） |
| 授权 | **没有权限概念**，只有登录门的开合 | 9 个模块 × 8 把权限键 |
| 本地存储键 | `yuanbao.market.buyer.session` | `bufang.auth` |
| 到期（402） | 不存在这条路 | 除设置 / 反馈外全部锁 |

两条铁律：**① 两套凭证永不互换**（同一个设备上两套并存；一个壳里做双账号也必须两个独立存储）；**② 库存端文档的任何规则都不自动适用于公域端**，反之亦然——它们的身份体系不是一回事。

---

## 结语

这份文档的核心只有一句话：**公域端是一个买来的广告落地页的客户端，它唯一的真相来源是投影表与服务端出参。**

重写时请守住四件事：

1. **不要绕过 `/api/market/*` 直连 Supabase**——投影表之外没有买家该看的东西，而直连会绕过掩码、限流、归因，以及那句「金额必须服务端重算」。
2. **不要相信任何来自客户端的身份、号码、金额、坑位、语言**：`X-Buyer-Session` 是凭证不是身份，金额由服务端按投影价重算，`slot_kind` 一类由服务端从 `pool` 推出。
3. **不要把「读不到」画成「没有」**：`null` 走隐藏或「未取到」，`0` 走「真的是零」，两者永远不共用一个渲染分支。
4. **不要把两套凭证混起来**：买家会话与租户会话在同一个设备上共存，一次互换就是一次账号事故。

凡本文档写了「现网恒为 / 从未 / 全为 `NULL`」的地方，**先看日期再看结论**（§11.3 就是为这件事存在的）；未在本文档出现的行为，一律视为「未验证」，落地前先实测。
