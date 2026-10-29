import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';

/// Trang sinh viên: các lớp đã vào, tỉ lệ đi học, cảnh báo nguy cơ cấm thi, quét QR điểm danh
class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  late Future<dynamic> _history = Api.get('Attendance/history');

  Future<void> _reload() async {
    setState(() => _history = Api.get('Attendance/history'));
    await _history;
  }

  Future<void> _join() async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vào lớp'),
        content: TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Mã lớp do giảng viên cung cấp', prefixIcon: Icon(Icons.key)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vào lớp')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await guard(context, () => Api.post('Courses/join', {'joinCode': code.text.trim()})) != null) _reload();
  }

  Future<void> _scan() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Điểm danh'),
      actions: [
        IconButton(tooltip: 'Vào lớp', icon: const Icon(Icons.group_add_outlined), onPressed: _join),
        profileAction(context),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _scan,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Quét QR điểm danh'),
    ),
    body: AsyncView(
      future: _history,
      onRefresh: _reload,
      builder: (courses) {
        final warnings = courses.where((c) => c['warning'] == true).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          Text('Xin chào, ${Auth.fullName}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (warnings.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, size: 32),
                title: const Text('Nguy cơ cấm thi', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Bạn vắng quá 20% số buổi ở: ${warnings.map((c) => c['code']).join(', ')}'),
              ),
            ),
          if (courses.isEmpty)
            SizedBox(
              height: 360,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.school_outlined, size: 56),
                const SizedBox(height: 12),
                const Text('Bạn chưa vào lớp nào'),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(onPressed: _join, icon: const Icon(Icons.group_add), label: const Text('Nhập mã lớp')),
              ]),
            ),
          for (final c in courses) _CourseCard(course: c, onLeft: _reload),
        ]);
      },
    ),
  );
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onLeft});
  final Map course;
  final VoidCallback onLeft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final int total = course['totalSessions'];
    final int absent = course['absent'];
    final double rate = (course['absentRate'] as num).toDouble();
    final bool warning = course['warning'];
    final List sessions = course['sessions'];
    final color = warning ? scheme.error : (rate >= 0.15 ? Colors.orange : Colors.green);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text('${course['code']} · ${course['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 6),
          LinearProgressIndicator(value: total == 0 ? 0 : 1 - rate, color: color, borderRadius: BorderRadius.circular(4), minHeight: 6),
          const SizedBox(height: 4),
          Text(total == 0
              ? 'Chưa có buổi nào'
              : 'Vắng $absent/$total buổi (${(rate * 100).toStringAsFixed(0)}%)${warning ? ' – nguy cơ cấm thi' : ''}',
              style: TextStyle(color: warning ? scheme.error : null)),
        ]),
        children: [
          for (final s in sessions)
            ListTile(
              dense: true,
              title: Text(s['title']),
              subtitle: Text(fmtDate(s['startAt'], withYear: true)),
              trailing: StatusChip(s['status']),
            ),
          TextButton.icon(
            onPressed: () async {
              if (!await confirm(context, 'Rời lớp ${course['code']}? Lịch sử điểm danh của lớp này sẽ bị xoá.') || !context.mounted) return;
              if (await guard(context, () => Api.delete('Courses/${course['id']}/leave')) != null) onLeft();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Rời lớp'),
          ),
        ],
      ),
    );
  }
}
