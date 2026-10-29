import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api.dart';
import '../face/face_scan_screen.dart';
import '../main.dart';
import '../widgets.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

/// Khung chung của màn đăng nhập/đăng ký: đầu trang màu + logo
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 32, 24, 32),
            decoration: const BoxDecoration(
              gradient: kBrandGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(children: [
              const CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: Icon(Icons.how_to_reg_rounded, size: 40, color: kGold),
              ),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: kInk.withValues(alpha: 0.75))),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(24), child: child),
        ]),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController(text: Auth.userName);
  final _pass = TextEditingController();
  bool _busy = false;
  bool _showPass = false;
  static bool _googleReady = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  void _goHome(Map<String, dynamic> result) async {
    await Auth.save(result);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeFor(Auth.role)), (_) => false);
  }

  /// Tên đăng nhập + mật khẩu → server gửi OTP về email → màn nhập OTP
  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final r = await guard(context, () => Api.post('Auth/login', {
        'userName': _user.text.trim(),
        'password': _pass.text,
      }), showSuccess: false);
      if (r == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(userName: _user.text.trim(), password: _pass.text, sentTo: r['sentTo']),
      ));
    });
  }

  /// OAuth 2.0: Google trả ID token, server kiểm tra token với Google rồi cấp JWT của app
  Future<void> _google() => _run(() async {
    final clientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
    if (clientId.isEmpty) {
      showMsg(context, 'Chưa cấu hình Google Sign-In: điền GOOGLE_WEB_CLIENT_ID trong file .env (xem README mục 5)', error: true);
      return;
    }
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: clientId);
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw ApiException('Google không trả về ID token');
      if (!mounted) return;
      final r = await guard(context, () => Api.post('Auth/google', {'idToken': idToken}), showSuccess: false);
      if (r != null) _goHome(r);
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled && mounted) {
        showMsg(context, 'Đăng nhập Google lỗi: ${e.description ?? e.code.name}', error: true);
      }
    }
  });

  /// Quét mặt (có kiểm tra nháy mắt) → gửi vector 2 ảnh lên server so với khuôn mặt đã đăng ký
  Future<void> _face() async {
    if (_user.text.trim().isEmpty) {
      showMsg(context, 'Nhập tên đăng nhập trước khi quét khuôn mặt', error: true);
      return;
    }
    final embeddings = await Navigator.of(context).push<List<List<double>>>(
      MaterialPageRoute(builder: (_) => const FaceScanScreen(title: 'Đăng nhập bằng khuôn mặt', shots: 2)),
    );
    if (embeddings == null || !mounted) return;
    await _run(() async {
      final r = await guard(context, () => Api.post('Auth/face-login', {
        'userName': _user.text.trim(),
        'embeddings': embeddings,
      }), showSuccess: false);
      if (r != null) _goHome(r);
    });
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Điểm danh SV',
    subtitle: 'Điểm danh nhanh bằng QR, GPS và khuôn mặt',
    child: Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Field(_user, 'Tên đăng nhập hoặc email', icon: Icons.person_outline, validator: notEmpty),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: _pass,
            obscureText: !_showPass,
            validator: notEmpty,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
        ),
        Text('Mã OTP sẽ được gửi về email của tài khoản', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Đăng nhập'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [Expanded(child: Divider()), Text('  hoặc  '), Expanded(child: Divider())]),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _google,
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.redAccent)),
          label: const Text('Tiếp tục với Google'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _face,
          icon: const Icon(Icons.face_retouching_natural),
          label: const Text('Đăng nhập bằng khuôn mặt'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
          child: const Text('Chưa có tài khoản? Đăng ký bằng email'),
        ),
      ]),
    ),
  );
}
