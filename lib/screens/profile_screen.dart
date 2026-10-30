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

/// Cỡ chữ, màu nền, màu ô: đổi là áp dụng ngay cho cả app, lưu trên máy
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ListenableBuilder(
        listenable: AppSettings.all,
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
            _swatches(context, Icons.palette_outlined, 'Màu nền', AppSettings.backgrounds, AppSettings.background.value, AppSettings.setBackground),
            const SizedBox(height: 20),
            _swatches(context, Icons.dashboard_outlined, 'Màu ô', AppSettings.cards, AppSettings.card.value, AppSettings.setCard),
          ]);
        },
      ),
    ),
  );

  /// Hàng màu có sẵn + ô cầu vồng cuối hàng để tự chọn màu bằng thanh kéo
  Widget _swatches(BuildContext context, IconData icon, String title, Map<String, Color> colors, Color current,
      ValueChanged<Color> onPick) {
    final custom = !colors.containsValue(current);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon), const SizedBox(width: 16), Text(title)]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final MapEntry(key: name, value: color) in colors.entries)
          _swatch(label: '$title $name', selected: current == color, onTap: () => onPick(color), color: color),
        _swatch(
          label: '$title tuỳ chỉnh',
          selected: custom,
          color: custom ? current : null,
          onTap: () async {
            final picked = await _pickColor(context, title, current);
            if (picked != null) onPick(picked);
          },
        ),
      ]),
    ]);
  }

  /// Ô tròn chọn màu; color null là ô cầu vồng "tuỳ chỉnh"
  Widget _swatch({required String label, required bool selected, required VoidCallback onTap, Color? color}) => Semantics(
    label: label,
    selected: selected,
    button: true,
    child: Tooltip(
      message: label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: CircleAvatar(
          radius: 22,
          backgroundColor: selected ? kGold : kCreamDeep,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              gradient: color == null ? SweepGradient(colors: _hues(0.8)) : null,
            ),
            child: selected ? const Icon(Icons.check, color: kInk) : (color == null ? const Icon(Icons.colorize, color: kInk, size: 20) : null),
          ),
        ),
      ),
    ),
  );
}

/// Dải 7 màu cầu vồng (đỏ → đỏ) ở độ sáng [light]
List<Color> _hues(double light) => [for (var h = 0; h <= 360; h += 60) HSLColor.fromAHSL(1, h.toDouble(), 0.7, light).toColor()];

/// Hộp chọn màu: thanh sắc màu + thanh độ nhạt. Độ sáng chặn ≥ 75% để chữ nâu đậm vẫn đọc rõ
Future<Color?> _pickColor(BuildContext context, String title, Color initial) {
  final start = HSLColor.fromColor(initial);
  var hue = start.hue;
  var light = start.lightness.clamp(0.75, 0.98);
  Color color() => HSLColor.fromAHSL(1, hue, 0.7, light).toColor();
  return showDialog<Color>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('$title tuỳ chỉnh'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: color(),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kCreamDeep),
            ),
            alignment: Alignment.center,
            child: const Text('Chữ mẫu', style: TextStyle(color: kInk, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          const Text('Sắc màu'),
          _GradientSlider(
            label: 'Sắc màu',
            colors: _hues(0.6),
            value: hue,
            max: 360,
            onChanged: (v) => setState(() => hue = v),
          ),
          const Text('Độ nhạt'),
          _GradientSlider(
            label: 'Độ nhạt',
            colors: [HSLColor.fromAHSL(1, hue, 0.7, 0.75).toColor(), Colors.white],
            value: light,
            min: 0.75,
            max: 0.98,
            onChanged: (v) => setState(() => light = v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, color()), child: const Text('Chọn')),
        ],
      ),
    ),
  );
}

/// Slider của Material (kéo, bấm, đọc màn hình đều được) đặt trên một dải màu gradient
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.colors,
    required this.value,
    required this.onChanged,
    this.min = 0,
    required this.max,
  });
  final String label;
  final List<Color> colors;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
    Container(
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 24), // khớp phần lề của Slider
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: LinearGradient(colors: colors)),
    ),
    SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: Colors.transparent,
        inactiveTrackColor: Colors.transparent,
        thumbColor: kInk,
      ),
      child: Slider(value: value, min: min, max: max, label: label, semanticFormatterCallback: (_) => label, onChanged: onChanged),
    ),
  ]);
}
