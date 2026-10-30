import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import '../api.dart';
import '../face/face_math.dart';
import '../face/face_scan_screen.dart';
import '../settings.dart';
import '../widgets.dart';
import 'login_screen.dart';

/// Nút mở Hồ sơ & cài đặt trên AppBar của mọi trang
Widget profileAction(BuildContext context) => IconButton(
  tooltip: 'Hồ sơ & cài đặt',
  // nền trắng để nổi trên đầu trang màu gradient
  icon: ValueListenableBuilder(
    valueListenable: Auth.avatar,
    builder: (_, image, _) => Avatar(Auth.fullName, radius: 18, image: image, background: Colors.white),
  ),
  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
);

/// Hồ sơ & cài đặt: ảnh đại diện, sửa thông tin, khuôn mặt, vân tay, mật khẩu, cỡ chữ, màu nền, đăng xuất
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<dynamic> _me = Api.get('Auth/me');

  Future<void> _reload() async {
    setState(() { _me = Api.get('Auth/me'); });
    await _me.catchError((_) => null); // lỗi đã hiện trong AsyncView
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

  /// Ảnh lấy từ thư viện/camera, thu nhỏ còn 256px ngay khi chọn rồi gửi base64 lên server
  Future<void> _changeAvatar(bool hasAvatar) async {
    const remove = 'remove';
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(c, ImageSource.camera)),
          if (hasAvatar)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Xoá ảnh đại diện'),
                onTap: () => Navigator.pop(c, remove)),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    String? data;
    if (choice is ImageSource) {
      final file = await ImagePicker().pickImage(source: choice, maxWidth: 256, maxHeight: 256, imageQuality: 80);
      if (file == null) return;
      data = base64Encode(await file.readAsBytes());
    }
    if (!mounted) return;
    if (await guard(context, () => Api.put('Auth/avatar', {'avatar': data})) != null) {
      await Auth.setAvatar(data);
      _reload();
    }
  }

  /// Bật: quét vân tay để chắc chính chủ rồi xin khoá từ server. Tắt: xoá khoá cả trên máy và server
  Future<void> _toggleBiometric(bool on) async {
    try {
      if (on) {
        final ok = await LocalAuthentication().authenticate(
          localizedReason: 'Xác nhận vân tay để bật đăng nhập bằng vân tay',
          biometricOnly: true,
        );
        if (!ok) return;
        await Auth.enableBiometric();
      } else {
        await Auth.disableBiometric();
      }
      if (mounted) showMsg(context, on ? 'Lần sau có thể đăng nhập bằng vân tay' : 'Đã tắt đăng nhập bằng vân tay');
    } on LocalAuthException catch (e) {
      if (mounted) showMsg(context, 'Vân tay: ${e.description ?? e.code.name}', error: true);
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
    }
    if (mounted) setState(() {});
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
    if (r == null) return;
    if (Auth.biometricUser == Auth.userName) await Auth.forgetBiometric(); // server đã tắt vân tay khi đổi mật khẩu
    _reload();
  }

  Future<void> _logout() async {
    await Auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hồ sơ & cài đặt')),
    body: AsyncView(
      future: _me,
      onRefresh: _reload,
      builder: (me) {
        return ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Semantics(
              button: true,
              label: 'Đổi ảnh đại diện',
              child: GestureDetector(
                onTap: () => _changeAvatar(me['avatar'] != null),
                child: Stack(children: [
                  Avatar(me['fullName'], radius: 44, color: roleColors[me['role']], image: me['avatar']),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(radius: 14, backgroundColor: kGold,
                        child: Icon(Icons.photo_camera, size: 16, color: Colors.white)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(me['fullName'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Center(child: RoleChip(me['role'])),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              ListTile(leading: const Icon(Icons.person_outline), title: const Text('Tên đăng nhập'), subtitle: Text(me['userName'])),
              ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(me['email'] ?? '')),
              ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('Số điện thoại'), subtitle: Text(me['phoneNumber'] ?? 'Chưa có')),
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
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Đăng nhập bằng vân tay'),
                subtitle: const Text('Tự bật sau lần đăng nhập mật khẩu đầu tiên'),
                value: Auth.biometricUser == Auth.userName,
                onChanged: _toggleBiometric,
              ),
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(me['hasPassword'] ? 'Đổi mật khẩu' : 'Đặt mật khẩu'),
                onTap: () => _changePassword(me['hasPassword']),
              ),
            ]),
          ),
          const _AppearanceCard(),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Đăng xuất')),
        ]);
      },
    ),
  );
}

/// Cỡ chữ và màu nền: đổi là áp dụng ngay cho cả app, lưu trên máy
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListenableBuilder(
        listenable: Listenable.merge([AppSettings.textScale, AppSettings.background]),
        builder: (context, _) {
          final percent = '${(AppSettings.textScale.value * 100).round()}%';
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.format_size), const SizedBox(width: 16), Text('Cỡ chữ $percent')]),
            Slider(
              value: AppSettings.textScale.value,
              min: 0.8,
              max: 1.4,
              divisions: 6,
              label: percent,
              onChanged: AppSettings.setTextScale,
            ),
            const Row(children: [Icon(Icons.palette_outlined), SizedBox(width: 16), Text('Màu nền')]),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final MapEntry(key: name, value: color) in AppSettings.backgrounds.entries)
                Semantics(
                  label: 'Nền $name',
                  selected: AppSettings.background.value == color,
                  button: true,
                  child: Tooltip(
                    message: name,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => AppSettings.setBackground(color),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: AppSettings.background.value == color ? kGold : kCreamDeep,
                        child: CircleAvatar(
                          radius: 19,
                          backgroundColor: color,
                          child: AppSettings.background.value == color ? const Icon(Icons.check, color: kInk) : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        },
      ),
    ),
  );
}
