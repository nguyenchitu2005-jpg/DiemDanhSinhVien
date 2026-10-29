import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'otp_screen.dart';

/// Đăng ký tài khoản sinh viên bằng email: server gửi OTP về email để xác nhận
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post('Auth/register', {
      'fullName': _name.text.trim(),
      'studentCode': _code.text.trim(),
      'userName': _user.text.trim(),
      'email': _email.text.trim(),
      'phoneNumber': _phone.text.trim(),
      'password': _pass.text,
    }), showSuccess: false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => OtpScreen(userName: _user.text.trim(), password: _pass.text, channel: 'email', sentTo: r['sentTo']),
    ));
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Đăng ký',
    subtitle: 'Tạo tài khoản sinh viên bằng email',
    child: Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Field(_name, 'Họ và tên', icon: Icons.badge_outlined, validator: notEmpty),
        Field(_code, 'Mã sinh viên', icon: Icons.numbers),
        Field(_user, 'Tên đăng nhập', icon: Icons.person_outline,
            validator: (v) => v == null || !RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch(v.trim())
                ? '3–30 ký tự: chữ không dấu, số, . _ -'
                : null),
        Field(_email, 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress,
            validator: (v) => v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Email không hợp lệ'),
        Field(_phone, 'Số điện thoại (để nhận OTP qua SMS)', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
        Field(_pass, 'Mật khẩu', icon: Icons.lock_outline, obscure: true,
            hint: 'Có chữ hoa, chữ thường, số và ký tự đặc biệt',
            validator: (v) => v == null || v.length < 6 ? 'Tối thiểu 6 ký tự' : null),
        Field(_pass2, 'Nhập lại mật khẩu', icon: Icons.lock_outline, obscure: true,
            validator: (v) => v != _pass.text ? 'Mật khẩu không khớp' : null),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Đăng ký'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đã có tài khoản? Đăng nhập')),
      ]),
    ),
  );
}
