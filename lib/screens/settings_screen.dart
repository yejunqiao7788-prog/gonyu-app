import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import 'auth_screen.dart';

/// 设置：语言、改密、注销、登出。
/// 改密不是登出：当前会话继续存活，提示「其他设备需要重新登录」（§4.3）。
/// 注销入口必须是显式的，并说清后果（§9.4）——本轮不上架，但入口的形状现在就定。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePassword() async {
    final l = _app.l10n;
    final current = TextEditingController();
    final next = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.raw('change_password')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: current, obscureText: true, decoration: InputDecoration(labelText: l.raw('current_password'))),
            const SizedBox(height: 10),
            TextField(controller: next, obscureText: true, decoration: InputDecoration(labelText: l.raw('new_password'), helperText: l.raw('password_rule'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.raw('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.raw('save'))),
        ],
      ),
    );
    if (submitted != true) return;
    try {
      // 密码原文提交：不 trim、不折叠空白（§4.2）。
      await _app.buyerAuthApi.changePassword(currentPassword: current.value.text, newPassword: next.value.text);
      if (mounted) _toast(l.raw('password_changed'));
    } on MarketApiException catch (e) {
      if (mounted) _toast(_app.describeError(e) ?? '');
    } finally {
      current.dispose();
      next.dispose();
    }
  }

  Future<void> _closeAccount() async {
    final l = _app.l10n;
    final pw = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.raw('close_account')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.raw('close_account_warning'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: l.raw('current_password'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.raw('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.raw('close_account'), style: const TextStyle(color: Color(0xFFB3261E)))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _app.buyerAuthApi.closeAccount(currentPassword: pw.value.text);
      // 服务端墓碑 + finally 清本地；注销后的买家没有个人页可读（§4.8）。
      await _app.logout();
      if (mounted) _toast(l.raw('account_closed'));
    } on MarketApiException catch (e) {
      if (mounted) _toast(_app.describeError(e) ?? '');
    } finally {
      pw.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.raw('settings'))),
      body: ListView(
        children: [
          // ---- 语言 ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l.raw('language'), style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final lang in l.langs)
            ListTile(
              title: Text(l.raw('lang_$lang')),
              trailing: lang == _app.lang ? const Icon(Icons.check, color: MarketTokens.primary) : null,
              onTap: () async {
                // 只有这里的一次显式点击才写偏好；自动检测结果永不落盘（§9.6）。
                await _app.setLang(lang);
                setState(() {});
              },
            ),
          const Divider(),
          if (_app.signedIn) ...[
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(l.raw('change_password')),
              onTap: _changePassword,
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l.raw('logout')),
              onTap: () async {
                await _app.logout(); // finally 里清本地行（§4.3）
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: MarketTokens.primary),
              title: Text(l.raw('close_account'), style: const TextStyle(color: Color(0xFFB3261E))),
              onTap: _closeAccount,
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: Text(l.raw('login')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(initialMode: 'login'))),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${_app.l10n.raw('app_name')} · ${Theme.of(context).platform == TargetPlatform.iOS ? 'iPhone' : 'Android'} v0.1.0', style: Theme.of(context).textTheme.bodySmall?.apply(color: MarketTokens.muted)),
          ),
        ],
      ),
    );
  }
}
