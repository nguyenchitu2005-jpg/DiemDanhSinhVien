import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

void showMsg(BuildContext context, Object message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message.toString()),
      backgroundColor: error ? scheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Chạy 1 lời gọi API: lỗi thì hiện thông báo đỏ và trả null; thành công thì hiện "message" của API (nếu có)
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {bool showSuccess = true}) async {
  try {
    final result = await action();
    if (showSuccess && context.mounted && result is Map && result['message'] != null) showMsg(context, result['message']);
    return result;
  } catch (e) {
    if (context.mounted) showMsg(context, e is ApiException ? e.message : 'Lỗi: $e', error: true);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đồng ý')),
        ],
      ),
    ) ??
    false;

/// Hiện dữ liệu của 1 Future: đang tải / lỗi (nút thử lại) / kéo xuống để tải lại
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.onRefresh, required this.builder});

  final Future<T> future;
  final Future<void> Function() onRefresh;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(snap.error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRefresh, child: const Text('Thử lại')),
            ]),
          ),
        );
      }
      return RefreshIndicator(onRefresh: onRefresh, child: builder(snap.data as T));
    },
  );
}

/// Danh sách rỗng mà vẫn kéo xuống để tải lại được
class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListView(children: [
    const SizedBox(height: 120),
    Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
    const SizedBox(height: 12),
    Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
  ]);
}

/// Trạng thái điểm danh → nhãn + màu
const attendanceLabels = {
  'Present': ('Có mặt', Colors.green),
  'Late': ('Đi muộn', Colors.orange),
  'Excused': ('Có phép', Colors.blue),
  'Absent': ('Vắng', Colors.red),
  'Open': ('Đang mở', Colors.grey),
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = attendanceLabels[status] ?? (status, Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

const roleLabels = {'Admin': 'Quản trị', 'Teacher': 'Giảng viên', 'Student': 'Sinh viên'};
const roleColors = {'Admin': Colors.deepPurple, 'Teacher': Colors.teal, 'Student': Colors.indigo};

/// Tông màu của app: vàng kem + trắng
const kGold = Color(0xFFD9A73E); // vàng đậm: màu gốc của theme, viền, điểm nhấn
const kCream = Color(0xFFFFF6DE); // kem nhạt
const kCreamDeep = Color(0xFFFFE4A1); // kem đậm
const kInk = Color(0xFF4A3712); // chữ nâu đậm, đọc rõ trên nền kem
const kBrandGradient = LinearGradient(colors: [kCreamDeep, kCream], begin: Alignment.topLeft, end: Alignment.bottomRight);

/// Chữ cái đầu của tên (tên Việt: lấy chữ cuối, "Nguyễn Văn An" → "A")
String initials(String? name) {
  final last = (name ?? '').trim().split(RegExp(r'\s+')).last;
  return last.isEmpty ? '?' : last[0].toUpperCase();
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.color, this.radius = 20});
  final String? name;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withValues(alpha: 0.15),
      child: Text(initials(name), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: radius * 0.8)),
    );
  }
}

class RoleChip extends StatelessWidget {
  const RoleChip(this.role, {super.key});
  final String? role;

  @override
  Widget build(BuildContext context) {
    final color = roleColors[role] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(roleLabels[role] ?? '-', style: TextStyle(color: color.shade700, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Ô thống kê trên đầu trang: (biểu tượng, số, nhãn)
typedef Stat = (IconData, String, String);

/// Đầu trang chủ có dải màu giống màn đăng nhập: lời chào, nút hồ sơ, các ô thống kê, TabBar (nếu có)
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.title, required this.subtitle, this.actions = const [], this.stats = const [], this.bottom});
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Stat> stats;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark, // chữ thanh trạng thái màu tối trên nền kem
    child: Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 12, bottom == null ? 20 : 0),
      decoration: const BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subtitle, style: TextStyle(color: kInk.withValues(alpha: 0.7))),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kInk, fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
          ),
          ...actions,
        ]),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              for (final (icon, value, label) in stats)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      Icon(icon, color: kGold, size: 20),
                      const SizedBox(height: 4),
                      Text(value, style: const TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(label, style: TextStyle(color: kInk.withValues(alpha: 0.7), fontSize: 12)),
                    ]),
                  ),
                ),
            ]),
          ),
        ],
        ?bottom,
      ]),
    ),
  );
}

/// Ô vuông bo góc chứa biểu tượng, đặt đầu thẻ
class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: c),
    );
  }
}

/// Ngày giờ UTC từ API → giờ máy, dạng 29/10 14:05
String fmtDate(String? iso, {bool withYear = false}) {
  if (iso == null) return '';
  final d = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}${withYear ? '/${d.year}' : ''} ${two(d.hour)}:${two(d.minute)}';
}

/// Ô nhập có nhãn, dùng trong form
class Field extends StatelessWidget {
  const Field(this.controller, this.label,
      {super.key, this.icon, this.obscure = false, this.keyboard, this.validator, this.hint});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon == null ? null : Icon(icon)),
    ),
  );
}

String? notEmpty(String? v) => v == null || v.trim().isEmpty ? 'Không được để trống' : null;

/// Đúng luật mật khẩu mặc định của ASP.NET Identity trên server, báo lỗi tiếng Việt ngay khi nhập
String? strongPassword(String? v) {
  final p = v ?? '';
  if (p.length < 6) return 'Tối thiểu 6 ký tự';
  if (!p.contains(RegExp('[A-Z]'))) return 'Cần ít nhất 1 chữ in hoa';
  if (!p.contains(RegExp('[a-z]'))) return 'Cần ít nhất 1 chữ thường';
  if (!p.contains(RegExp('[0-9]'))) return 'Cần ít nhất 1 chữ số';
  if (!p.contains(RegExp('[^a-zA-Z0-9]'))) return 'Cần ít nhất 1 ký tự đặc biệt (vd @ # !)';
  return null;
}

/// Dòng chữ trạng thái đổi có hiệu ứng mờ dần (chép từ project faceid, dùng ở màn quét khuôn mặt).
/// Khoá là số đếm tăng dần chứ không phải nội dung: chữ đổi A → B → A quá nhanh sẽ trùng khoá trong AnimatedSwitcher.
class FadingStatusText extends StatefulWidget {
  const FadingStatusText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<FadingStatusText> createState() => _FadingStatusTextState();
}

class _FadingStatusTextState extends State<FadingStatusText> {
  int _version = 0;

  @override
  void didUpdateWidget(FadingStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _version++;
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 200),
    child: Text(widget.text, key: ValueKey(_version), textAlign: widget.textAlign, style: widget.style),
  );
}
