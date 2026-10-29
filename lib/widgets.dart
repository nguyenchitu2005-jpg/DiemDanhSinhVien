import 'package:flutter/material.dart';

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
