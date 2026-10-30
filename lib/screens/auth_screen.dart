import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../state/app_state.dart';

/// 登录/注册（§4.2、§4.5）。要点：
/// - 名称 2–40、密码 8–64 由服务端裁决，输入框 maxLength 不是判据；App 只做友好预检，最终以码分派。
/// - 密码绝不 trim、不折叠空白——那是两个不同的密码。
/// - 只有 401 显示「账号或密码不对」；403 封禁是它自己的一句话，不给重试按钮。
/// - 软锁 429 BUYER_LOGIN_LOCKED 用服务端 retry_after_seconds 倒计时，不自己数 15 分钟。
/// - 没有「忘记密码」入口：公域端不存在找回路径（M8-B SMS OTP 未建），放了就没有后端可接。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialMode = 'login'});
  final String initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late final AppState _app;
  late bool _isRegister = widget.initialMode == 'register';
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _consent = false; // 营销同意默认关闭（§9.4）
  String? _phoneError;
  String? _passwordError;
  String? _nameError;
  String? _bannerError;
  int _lockCountdown = 0;
  Timer? _lockTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockCountdown = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _lockCountdown--);
      if (_lockCountdown <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    if (_busy || _lockCountdown > 0) return;
    setState(() {
      _busy = true;
      _phoneError = _passwordError = _nameError = _bannerError = null;
    });
    try {
      if (_isRegister) {
        await _app.register(name: _name.text, phone: _phone.text, password: _password.value.text, consentMarketing: _consent);
      } else {
        await _app.login(phone: _phone.text, password: _password.value.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on MarketApiException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'INVALID_PHONE':
            _phoneError = e.code;
            break;
          case 'INVALID_NAME':
            _nameError = e.code;
            break;
          case 'INVALID_PASSWORD':
            _passwordError = e.code;
            break;
          case 'BUYER_INVALID_CREDENTIALS':
            _passwordError = e.code; // 只标字段，不叫「重新登录」
            break;
          case 'BUYER_PHONE_REGISTERED':
            _bannerError = e.code; // 直接引导去登录，不报「注册失败」
            _isRegister = false;
            break;
          case 'BUYER_LOGIN_LOCKED':
            _bannerError = e.code;
            _startLockCountdown(e.retryAfterSeconds ?? 900);
            break;
          case 'BUYER_ACCOUNT_SUSPENDED':
            _bannerError = e.code; // 一句话说明被处置，不给重试按钮
            break;
          default:
            _bannerError = '__generic';
            _app.describeError(e);
        }
        if (e.code == 'BUYER_PHONE_REGISTERED') _bannerError = e.code;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _fieldErrorText(String? code) {
    if (code == null) return null;
    return _app.l10n.errorText(MarketApiException(status: 400, code: code));
  }

  @override
  Widget build(BuildContext context) {
    final l = _app.l10n;
    final banner = _bannerError == null ? null : l.errorText(MarketApiException(status: 0, code: _bannerError == '__generic' ? 'NETWORK' : _bannerError!));
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? l.raw('register_title') : l.raw('login_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.raw('lead_phone'), errorText: _fieldErrorText(_phoneError)),
              ),
              const SizedBox(height: 12),
              if (_isRegister)
                Column(
                  children: [
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(labelText: l.raw('account_name'), helperText: l.raw('name_rule'), errorText: _fieldErrorText(_nameError)),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              // 密码不做任何 trim/规范化：提交原文（§4.2）。
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: l.raw('password'), helperText: l.raw('password_rule'), errorText: _fieldErrorText(_passwordError)),
              ),
              if (_isRegister)
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  title: Text(l.raw('lead_consent'), style: Theme.of(context).textTheme.bodySmall),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              if (banner != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(10)),
                  child: Text(banner, style: const TextStyle(color: Color(0xFFB3261E))),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || _lockCountdown > 0 ? null : _submit,
                  child: Text(
                    _lockCountdown > 0 ? l.raw('err_login_locked').replaceAll('{s}', '$_lockCountdown') : (_isRegister ? l.raw('register') : l.raw('login')),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _isRegister = !_isRegister;
                  _bannerError = null;
                }),
                child: Text(_isRegister ? l.raw('switch_to_login') : l.raw('switch_to_register')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
