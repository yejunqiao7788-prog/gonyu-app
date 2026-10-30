import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../data/analytics_binding.dart';
import '../data/models.dart';
import '../screens/auth_screen.dart';
import '../state/app_state.dart';

/// 网页客服面板（§6.7）。三条不能改的行为：
/// - 买家唯一拥有的是一个随机 43 字符 base64url 的线程 token，线程只按它寻址；
///   出参里没有 tenant_id / listing_id。
/// - 没有 Realtime，两侧都是轮询：开线程 6 s、关线程 15 s；App 在 paused 时停轮询、
///   恢复时立即拉一次。
/// - after 游标而不是偏移：增量拉取传最后一条消息 id，返回增量——新消息不重复、不丢的唯一形状。
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.slug, required this.listingTitle, required this.buyerGateEnabled, this.initialToken});

  final String slug;
  final String listingTitle;
  final bool buyerGateEnabled;
  final String? initialToken;

  @override
  State<ChatPanel> createState() => ChatPanelState();
}

class ChatPanelState extends State<ChatPanel> with WidgetsBindingObserver {
  late final AppState _app;
  MarketChatState? thread;
  bool sending = false;
  String? inputError;
  int? _lastMessageId;
  Timer? _poll;
  bool _openTracked = false;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    WidgetsBinding.instance.addObserver(this);
    // 恢复既有线程：个人页/本地记住的 token 续上，而不是对同一个商品开第二条线程（§8.6 第 3 条）。
    _restoreAndPoll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollOnce(); // 恢复时立即拉一次
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel(); // paused 时停轮询
    }
  }

  Future<void> _restoreAndPoll() async {
    final token = widget.initialToken ?? await _app.credentials.chatTokenFor(widget.slug);
    if (token == null || !mounted) return;
    await _pollOnce(token: token);
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    final closed = thread?.status != 'open';
    _poll = Timer.periodic(Duration(seconds: closed ? 15 : 6), (_) => _pollOnce());
  }

  Future<void> _pollOnce({String? token}) async {
    final t = token ?? thread?.conversationToken ?? await _app.credentials.chatTokenFor(widget.slug);
    if (t == null) return;
    try {
      final fresh = await _app.marketApi.getChat(t, afterId: _lastMessageId);
      if (!mounted) return;
      setState(() {
        if (_lastMessageId == null) {
          thread = fresh;
        } else {
          thread = MarketChatMerger.append(thread!, fresh);
        }
        if (fresh.messages.isNotEmpty) _lastMessageId = fresh.messages.last.id;
      });
      _startPolling(); // closed/opened 切换会改变轮询节奏
      _scrollToEnd();
    } on MarketApiException catch (e) {
      if (!mounted) return;
      if (e.isSessionBroken || e.isLoginRequired) {
        setState(() => inputError = _app.l10n.errorText(e));
        _poll?.cancel();
      }
      // 其余失败：宁可显示上一次的消息 + 横幅，也不显示「没有消息」（§8.7）。
    } catch (_) {}
  }

  void _scrollToEnd() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // 硬登录门：门开着而未登录 → 弹登录，而不是发一条注定 401 的消息、也不是 toast 后什么都不做（§4.5）。
    if (widget.buyerGateEnabled && !_app.signedIn) {
      final signedIn = await openLoginFromChat(context);
      if (signedIn != true) return;
    }
    setState(() {
      sending = true;
      inputError = null;
    });
    try {
      if (thread == null) {
        final started = await _app.marketApi.startChat(slug: widget.slug, message: text, lang: _app.lang, sessionId: _app.analytics.sessionId);
        await _app.credentials.rememberChatToken(widget.slug, started.conversationToken ?? '');
        setState(() {
          thread = started;
          _lastMessageId = started.messages.isNotEmpty ? started.messages.last.id : null;
        });
      } else {
        final result = await _app.marketApi.sendChatMessage(thread!.conversationToken ?? '', text, _app.lang);
        final appended = result.appended;
        if (appended != null) {
          setState(() {
            thread = MarketChatMerger.withMessage(thread!, appended);
            _lastMessageId = appended.id;
          });
        }
        if (result.status != 'open') setState(() => _statusOverride = result.status);
      }
      _input.clear();
      _startPolling();
      _scrollToEnd();
    } on MarketApiException catch (e) {
      if (e.isLoginRequired || e.isSessionBroken) {
        if (e.isSessionBroken) await _app.credentials.clearSession();
        if (!mounted) return;
        setState(() => inputError = _app.l10n.errorText(e));
        if (widget.buyerGateEnabled) openLoginFromChat(context);
      } else if (mounted) {
        // 422 禁售词与「发送失败」分开展示，并保留买家已输入的文本——
        // 清空它等于丢劳动（§6.7、§12.2 ④）。
        setState(() => inputError = _app.l10n.errorText(e));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  String? _statusOverride;

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    // chat_open 埋点由面板侧一次 false→true 边沿记录（§8.8）。
    if (!_openTracked) {
      _openTracked = true;
      _app.analytics.track(AnalyticsBinding.chatOpen(widget.slug));
    }
    final t = thread;
    final status = _statusOverride ?? t?.status ?? 'open';
    final closed = status != 'open' && status != 'blocked';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(child: Text(t != null && t.listingTitle.isNotEmpty ? t.listingTitle : widget.listingTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        if (status == 'closed' || status == 'blocked')
          Container(width: double.infinity, color: MarketTokens.surfaceDim, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text(l.raw(status == 'blocked' ? 'chat_blocked' : 'chat_closed'))),
        Expanded(
          child: t == null
              ? Center(child: Text(l.raw('chat_first_message_hint'), style: Theme.of(context).textTheme.bodyMedium?.apply(color: MarketTokens.muted)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: t.messages.length,
                  itemBuilder: (_, i) {
                    final m = t.messages[i];
                    final mine = m.sender == 'buyer';
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: mine ? MarketTokens.primary : MarketTokens.surfaceDim,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m.body, style: TextStyle(color: mine ? Colors.white : MarketTokens.ink)),
                      ),
                    );
                  },
                ),
        ),
        if (inputError != null)
          Container(width: double.infinity, color: const Color(0xFFFFEBEE), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text(inputError!, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13))),
        if (!closed)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 2000, // MAX_MESSAGE_LEN，超限由服务端裁，本地只做提示
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: l.raw('chat_input_hint'), isDense: true, counterText: ''),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : send,
                    icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// after 游标的增量合并：GET 带 after 时返回的就是增量，直接追加。
class MarketChatMerger {
  static MarketChatState append(MarketChatState base, MarketChatState delta) {
    final known = base.messages.map((m) => m.id).toSet();
    final fresh = delta.messages.where((m) => !known.contains(m.id)).toList();
    if (fresh.isEmpty) return base;
    final merged = [...base.messages, ...fresh]..sort((a, b) => a.id.compareTo(b.id));
    final map = <String, dynamic>{'status': delta.status, 'seller_name': delta.sellerName, 'listing_title': delta.listingTitle, 'messages': merged.map((m) => m.toMap()).toList(), 'conversation_token': base.conversationToken};
    return MarketChatState.fromMap(map);
  }

  static MarketChatState withMessage(MarketChatState base, MarketChatMessage message) {
    final map = <String, dynamic>{'status': base.status, 'seller_name': base.sellerName, 'listing_title': base.listingTitle, 'messages': [...base.messages.map((m) => m.toMap()), message.toMap()].toList(), 'conversation_token': base.conversationToken};
    return MarketChatState.fromMap(map);
  }
}

Future<bool?> openLoginFromChat(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => AuthScreen()));
}
