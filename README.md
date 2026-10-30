# market_app — TorgSeek 公域集市买家 App

按 `market-app-development.md` v1.1（施工图）实现的公域端 App，走 **A 路线**：Flutter 调用
`https://www.torgseek.com/api/market/*` 的 26 条公开路由。不含租户控制台（`/app/*`）、
超管后台与公开展厅；与库存端 App（kucun-app）是两套身份、两个存储体系，永不互换。

## 已实现（对照文档章节）

| 模块 | 位置 | 关键契约 |
| --- | --- | --- |
| 传输层 | `lib/core/api_client.dart` | 信封解析、只按 `error.code` 分派、只重试 GET（500<<attempt，≤3 次）、`<` 开头按网关 HTML、逐端点超时（§3.3/§8.1 的档位，留资 45 s 永不自动重试） |
| 错误分档 | `lib/core/api_exception.dart` + `lib/core/l10n.dart` | §12.2 六组；会话三码归一句「请重新登录」；D4 的 5xx message 原样上屏；D3 的 expired/未知状态走默认分支 |
| 买家凭证 | `lib/core/credential_store.dart` | Keystore/Keychain 存 `yuanbao.market.buyer.session` `{token, expires_at}`；读时自逐出；>80 / <20 字符按未登录（§8.2/§8.3）；`X-Buyer-Session` 唯一构造点；客服线程 token 另存一处 |
| 浏览 | `lib/screens/home_screen.dart`、`lib/state/products_controller.dart`、`lib/widgets/listed_calendar.dart` | catalog 一次获取；采纳服务端回显 `page/sort`（越界回落第 1 页）；日历固定 30 天窗口、`truncated` 画下界、`reason` 整块不渲染；价格 300 ms 静默提交 + 卸载冲刷；空结果两类补救分开 |
| 详情/店铺 | `lib/screens/product_detail_screen.dart`、`lib/screens/seller_screen.dart` | `ttfr_hours`/`listing_count`/`rating` 的 null 按句子画；404 是终点整页；进店链接用 slug；`chat_enabled`/`buyer_gate_enabled` 只取出参（D2） |
| 留资 | `lib/screens/lead_form.dart` | 请求体没有金额字段；`use_saved_contact` 是意图不是值；按钮永远可点、错误码分档；营销同意默认不勾（§6.6/§7.3/§9.4） |
| 客服 | `lib/widgets/chat_panel.dart` | 一个面板实例；after 游标增量轮询（开 6 s / 关 15 s），`paused` 停轮询、恢复即拉；422 保留已输入文本；门开着先弹登录（§4.5/§6.7） |
| 账号 | `lib/data/buyer_auth_api.dart`、`lib/screens/auth_screen.dart`、`lib/screens/settings_screen.dart` | 13 条全走 X-Buyer-Session；密码不 trim 不折叠；软锁用服务端 `retry_after_seconds` 倒计时；改密不踢当前会话；登出/注销 `finally` 清本地；注销走服务端墓碑 |
| 收藏 | `lib/state/app_state.dart`、`lib/widgets/product_card.dart` | 服务端成员真相 + 本地缓存；迁移只发差集并记已交 slug；上限 200 与 `FAVORITES_FULL`；下架收藏仍可取消且仍列出但不给链接 |
| 埋点 | `lib/core/analytics.dart`、`lib/data/analytics_binding.dart` | 8 类词表不新增；队列 20 条/1.5 s，点击与销毁即 flush；曝光 40% 可见 + `${source}|${view}|${position}|${slug}` 去重、500 键封顶；`device_class` 自报（事件尺），UA 带平台词（归因尺）；无买家标识/号码/`slot_kind`（§6.9/§8.4/§8.9） |
| 四语 | `lib/core/lang_store.dart`、`lib/core/l10n_table.dart` | 解析链：深链 → 会话 → 显式选择 → 系统语言整列表 → uk；自动检测永不落盘；vi 读英文列；文案自成一包，与库存端 i18n 零耦合（§5.7/§9.6） |
| 分发 | `.github/workflows/build-apk.yml`、`build-ios.yml` | 云端构建（复用库存端 workflow 形状，只换产物名与包名）；二进制内零密钥（§9.1/§9.2） |

包名 `com.torgseek.market`（Android）/ `com.torgseek.marketApp`（iOS）。深链 scheme `torgseek://`
已声明，解析器在 `lib/main.dart` 的 `_DeepLink`（`/p/{slug}`、`/s/{seller}`、`?lang=`、`?chat=open`）。

## 已作出的架构决定（文档要求二选一的那些）

- **§11 A4（/track 归因）**：选择「App 不发 `/track`」。原生与 `www.torgseek.com` 不同源、
  `fbc/fbp/ttclid` 在原生不天然存在，做半套会让归因板长出最难解释的来源。归因由 H5 落地页
  那一跳负责，App 只上报自家行为事件（`/events` 照常）。
- **§11 A5（平台转化回传）**：不做，等服务端 CAPI（凭据进来之前的后端改动）。
- **`is_promoted`（§11 A1）**：渲染分支已实现（列表层给 true 就画「推广」，显式排序不摘标），
  现网暂无 true 可读数是观测缺口，不是客户端缺口。

## 本地验证与云端构建

本地已跑（Flutter 3.47.8 / Dart 3.13.7）：

```
flutter analyze   # 0 issues
flutter test      # 14 项核心纪律测试全过
```

APK / iOS 包按文档要求在 GitHub Actions 上构建，不在本机打签名包：

```
gh repo create   # 首次：建远端并推送
# push 到 main 后 Actions 自动出 app-release.apk（artifact: torgseek-market-release-apk）
```

## 待办 / 已知未观测项

- 深链接管（`app_links` 包或启动 intent 解析）与 assetlinks 域名验证——等业主决定是否由本 App 承接分享链接。
- 真机验收 §10 清单：留资一组是真写（需在测试租户上跑）；`FAVORITES_FULL`、`is_promoted=true` 两支按 §11 保持「未观测」。
- 启动图标暂用集市 PWA 图标铺满各密度档（无缩放工具链），要精修再补脚本。
