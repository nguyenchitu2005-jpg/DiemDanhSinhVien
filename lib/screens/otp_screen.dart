import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../main.dart';
import '../widgets.dart';
import 'login_screen.dart';

/// Nhập mã OTP 6 số (gửi qua email hoặc SMS) để hoàn tất đăng nhập / xác nhận email khi đăng ký
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.userName, required this.password, required this.channel, required this.sentTo});
  final String userName;
  final String password;
  final String channel;
  final String sentTo;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  int _wait = 30; // giây chờ trước khi được gửi lại mã
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _countdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _countdown() {
    _wait = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_wait <= 1) t.cancel();
      setState(() => _wait--);
    });
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      showMsg(context, 'Mã OTP gồm 6 chữ số', error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post('Auth/verify-otp', {
      'userName': widget.userName,
      'password': widget.password,
      'code': _code.text.trim(),
      'channel': widget.channel,
    }), showSuccess: false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    await Auth.save(r);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeFor(Auth.role)), (_) => false);
  }

  Future<void> _resend() async {
    final r = await guard(context, () => Api.post('Auth/login', {
      'userName': widget.userName,
      'password': widget.password,
      'channel': widget.channel,
    }), showSuccess: false);
    if (r != null && mounted) {
      showMsg(context, 'Đã gửi lại mã');
      _countdown();
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Xác thực OTP',
    subtitle: 'Mã đã gửi qua ${widget.channel == 'sms' ? 'SMS' : 'email'} tới ${widget.sentTo}',
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 30, letterSpacing: 12, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(counterText: '', hintText: '••••••'),
        onChanged: (v) {
          if (v.length == 6) _verify();
        },
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _verify,
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Xác nhận'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _wait > 0 ? null : _resend,
        child: Text(_wait > 0 ? 'Gửi lại mã sau $_wait giây' : 'Gửi lại mã'),
      ),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Quay lại')),
    ]),
  );
}
