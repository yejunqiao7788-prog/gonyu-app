import 'dart:async';
import 'dart:math';

import '../data/market_api.dart';
import 'api_client.dart';

/// 埋点通道：App 必须复刻 analytics.ts 的机械规则（§6.9、§8.9）。
/// - 队列 20 行或 1.5 s 冲刷；点击与页面销毁时立刻 flush（原生没有 keepalive 的必要，
///   但导航前冲刷仍然对——原生实现里页面也会被回收）。
/// - 曝光是「40% 可见一次」，绝不允许改成「渲染即曝光」：分母掺水会让 CPL 偏低（§7.6）。
/// - 去重键 `${source}|${view}|${position}|${slug}`，会话内 500 键封顶。
/// - 事件里永远没有买家标识、号码、buyer_token；slot_kind 永远不发（服务端从 pool 推）。
/// - /track（归因落地）App 侧不发：原生与 www 不同源，那是 §11 A4 的未决架构决定，
///   本 App 选择「归因由 H5 落地页那一跳负责，App 只上报行为事件」。
class Analytics {
  Analytics(this._api, {String Function()? sessionIdFactory})
      : _sessionId = sessionIdFactory != null ? sessionIdFactory() : _randomSessionId();

  final MarketApi _api;
  final String _sessionId;

  final List<MarketEventRow> _queue = [];
  Timer? _timer;
  final Set<String> _countedImpressions = {};
  static const int flushSize = 20;
  static const Duration flushDelay = Duration(milliseconds: 1500);
  static const int impressionCap = 500;

  static String _randomSessionId() => MarketApiClient.newRequestId();

  String get sessionId => _sessionId;

  String deviceClass = 'mobile'; // 由 UI 侧按屏宽设 mobile / tablet

  String _lang = 'uk';
  set lang(String v) => _lang = v;

  void track(MarketEventRow row) {
    _queue.add(row);
    if (_queue.length >= flushSize) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushDelay, () => unawaited(flush()));
    }
  }

  /// 曝光判据由 UI 侧的 VisibilityDetector（≥40%）触发后调用；这里只做会话内去重。
  /// view 是客户端去重键，不是持久判别字段——它不会出现在 mp_events 的任何一列里。
  bool shouldCountImpression({required String source, required String view, required int position, required String slug}) {
    final key = '$source|$view|$position|$slug';
    if (_countedImpressions.contains(key)) return false;
    if (_countedImpressions.length >= impressionCap) _countedImpressions.clear();
    _countedImpressions.add(key);
    return true;
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final batch = List<MarketEventRow>.of(_queue);
    _queue.clear();
    if (batch.length > 80) {
      // 单批 ≤ 80 行；超出按序切片（脏行会被服务端跳过而不是抛错）。
      for (int i = 0; i < batch.length; i += 80) {
        await _send(batch.sublist(i, min(i + 80, batch.length)));
      }
    } else {
      await _send(batch);
    }
  }

  Future<void> _send(List<MarketEventRow> batch) async {
    try {
      await _api.postEvents(sessionId: _sessionId, events: batch, deviceClass: deviceClass, lang: _lang);
    } catch (_) {
      // 埋点失败静默：它是平台自己的度量，不该打扰买家，也不该进重试风暴（8 s 超时即弃）。
    }
  }
}
