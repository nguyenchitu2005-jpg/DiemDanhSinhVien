import 'package:flutter/material.dart';

import '../api.dart';
import '../face/face_math.dart';
import '../face/face_scan_screen.dart';
import '../widgets.dart';
import 'login_screen.dart';

/// Nút mở Hồ sơ trên AppBar của mọi trang
Widget profileAction(BuildContext context) => IconButton(
  tooltip: 'Hồ sơ',
  // nền trắng để nổi trên đầu trang màu gradient
  icon: CircleAvatar(
    radius: 18,
    backgroundColor: Colors.white,
    child: Text(initials(Auth.fullName),
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
  ),
  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
);

/// Hồ sơ: sửa thông tin, đăng ký khuôn mặt, đổi mật khẩu, đăng xuất
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<dynamic> _me = Api.get('Auth/me');

  Future<void> _reload() async {
    setState(() { _me = Api.get('Auth/me'); });
    await _me;
  }

  Future<void> _edit(Map me) async {
    final name = TextEditingController(text: me['fullName']);
    final phone = TextEditingController(text: me['phoneNumber']);
    final code = TextEditingController(text: me['studentCode']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sửa thông tin'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Field(name, 'Họ và tên'),
            Field(phone, 'Số điện thoại', keyboard: TextInputType.phone),
            if (me['role'] == 'Student') Field(code, 'Mã sinh viên'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.put('Auth/me', {
      'fullName': name.text.trim(),
      'phoneNumber': phone.text.trim(),
      'studentCode': code.text.trim(),
    }));
    if (r != null) {
      Auth.fullName = name.text.trim();
      _reload();
    }
  }

  /// Chụp 5 ảnh (sau khi nháy mắt), lấy trung bình làm khuôn mặt mẫu lưu trên server
  Future<void> _registerFace() async {
    final embeddings = await Navigator.of(context).push<List<List<double>>>(
      MaterialPageRoute(builder: (_) => const FaceScanScreen(title: 'Đăng ký khuôn mặt', shots: 5)),
    );
    if (embeddings == null || !mounted) return;
    final r = await guard(context, () => Api.post('Auth/face', {'embedding': averageEmbeddings(embeddings)}));
    if (r != null) _reload();
  }

  Future<void> _changePassword(bool hasPassword) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(hasPassword ? 'Đổi mật khẩu' : 'Đặt mật khẩu'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hasPassword) Field(current, 'Mật khẩu hiện tại', obscure: true),
          Field(next, 'Mật khẩu mới', obscure: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('Auth/change-password', {'currentPassword': current.text, 'newPassword': next.text}));
    if (r != null) _reload();
  }

  Future<void> _logout() async {
    await Auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hồ sơ')),
    body: AsyncView(
      future: _me,
      onRefresh: _reload,
      builder: (me) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: Avatar(me['fullName'], radius: 44, color: roleColors[me['role']])),
          const SizedBox(height: 12),
          Text(me['fullName'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Center(child: RoleChip(me['role'])),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              ListTile(leading: const Icon(Icons.person_outline), title: const Text('Tên đăng nhập'), subtitle: Text(me['userName'])),
              ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(me['email'] ?? '')),
              ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('Số điện thoại'), subtitle: Text(me['phoneNumber'] ?? 'Chưa có (cần để nhận OTP qua SMS)')),
              if (me['role'] == 'Student')
                ListTile(leading: const Icon(Icons.numbers), title: const Text('Mã sinh viên'), subtitle: Text(me['studentCode'] ?? '')),
              ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Sửa thông tin'), onTap: () => _edit(me)),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: Icon(Icons.face, color: me['hasFace'] ? Colors.green : null),
                title: Text(me['hasFace'] ? 'Đăng ký lại khuôn mặt' : 'Đăng ký khuôn mặt'),
                subtitle: Text(me['hasFace'] ? 'Đã bật đăng nhập bằng khuôn mặt' : 'Để đăng nhập bằng khuôn mặt'),
                onTap: _registerFace,
              ),
              if (me['hasFace'])
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Xoá khuôn mặt'),
                  onTap: () async {
                    if (await confirm(context, 'Tắt đăng nhập bằng khuôn mặt?') && context.mounted) {
                      if (await guard(context, () => Api.delete('Auth/face')) != null) _reload();
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(me['hasPassword'] ? 'Đổi mật khẩu' : 'Đặt mật khẩu'),
                onTap: () => _changePassword(me['hasPassword']),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Đăng xuất')),
        ]);
      },
    ),
  );
}
