import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

/// 公域四语解析链（§5.7、§9.6），与库存端语言 store 零耦合、永不互读：
/// 深链 ?lang= → 本次会话上一次解析 → 上次显式选择 → 系统语言整条列表 → uk。
/// 自动检测的结果永远不写回偏好——否则第一次猜错就冻成永久。
class LangStore {
  static const List<String> marketLangs = ['uk', 'en', 'zh', 'vi'];
  static const String fallbackLang = 'uk';
  static const String chosenKey = 'yuanbao.market.lang'; // 只有显式切换才写

  String? _sessionLang; // 等价 sessionStorage：本进程内的上一次解析结果，不落盘

  String normalize(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return marketLangs.contains(v) ? v : fallbackLang;
  }

  /// en 与 vi 读英文内容列（readsEnglishContent），App 出参语言参数照常传本档。
  bool readsEnglishContent(String lang) => lang == 'en' || lang == 'vi';

  /// 解析当前语言。deeplinkLang 来自分享/落地链接的 ?lang=（命中即写入会话档）。
  Future<String> resolve({String? deeplinkLang}) async {
    final explicit = _inWhitelist(deeplinkLang);
    if (explicit != null) {
      _sessionLang = explicit;
      return explicit;
    }
    if (_sessionLang != null) return _sessionLang!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final chosen = _inWhitelist(prefs.getString(chosenKey));
      if (chosen != null) {
        _sessionLang = chosen;
        return chosen;
      }
    } catch (_) {}
    final auto = _detectFromSystemLocales();
    _sessionLang = auto; // 会话内保持，但不写偏好
    return auto;
  }

  /// LangSwitch 上的一次显式点击才落盘。
  Future<void> choose(String lang) async {
    final v = _inWhitelist(lang) ?? fallbackLang;
    _sessionLang = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(chosenKey, v);
    } catch (_) {}
  }

  String? _inWhitelist(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    return marketLangs.contains(v) ? v : null;
  }

  /// 扫整条系统语言列表，不是第一项：乌克兰设备的显示语言常是 en 而首选列表里有 uk。
  String _detectFromSystemLocales() {
    for (final locale in PlatformDispatcher.instance.locales) {
      final code = locale.languageCode.toLowerCase();
      if (marketLangs.contains(code)) return code;
    }
    return fallbackLang;
  }
}
