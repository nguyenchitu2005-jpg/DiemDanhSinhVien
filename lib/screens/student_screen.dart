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
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _scan,
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Quét QR điểm danh'),
    ),
    body: Column(children: [
      FutureBuilder(
        future: _history,
        builder: (_, snap) {
          final List courses = snap.data ?? [];
          final total = courses.fold<int>(0, (s, c) => s + (c['totalSessions'] as int));
          final absent = courses.fold<int>(0, (s, c) => s + (c['absent'] as int));
          return HomeHeader(
            subtitle: 'Sinh viên',
            title: Auth.fullName,
            actions: [
              IconButton(
                tooltip: 'Vào lớp',
                onPressed: _join,
                icon: const Icon(Icons.group_add_outlined, color: kInk),
              ),
              profileAction(context),
            ],
            stats: [
              (Icons.class_outlined, '${courses.length}', 'Lớp'),
              (Icons.verified_outlined, total == 0 ? '-' : '${((total - absent) * 100 / total).round()}%', 'Chuyên cần'),
              (Icons.event_busy_outlined, '$absent', 'Buổi vắng'),
            ],
          );
        },
      ),
      Expanded(
        child: AsyncView(
          future: _history,
          onRefresh: _reload,
          builder: (courses) {
            if (courses.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 100),
                Icon(Icons.school_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                const Text('Bạn chưa vào lớp nào', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.tonalIcon(onPressed: _join, icon: const Icon(Icons.group_add), label: const Text('Nhập mã lớp')),
                ),
              ]);
            }
            final warnings = courses.where((c) => c['warning'] == true).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
              if (warnings.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, size: 32),
                    title: const Text('Nguy cơ cấm thi', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Bạn vắng quá 20% số buổi ở: ${warnings.map((c) => c['code']).join(', ')}'),
                  ),
                ),
              Text('Lớp của tôi', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final c in courses) _CourseCard(course: c, onLeft: _reload),
            ]);
          },
        ),
      ),
    ]),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        // Vòng tròn % chuyên cần của lớp
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: total == 0 ? 0 : 1 - rate,
              strokeWidth: 5,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
            Text(total == 0 ? '-' : '${((1 - rate) * 100).round()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        ),
        title: Text(course['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          total == 0
              ? '${course['code']} · Chưa có buổi nào'
              : '${course['code']} · Vắng $absent/$total buổi${warning ? ' – nguy cơ cấm thi' : ''}',
          style: TextStyle(color: warning ? scheme.error : scheme.outline),
        ),
        children: [
          for (final s in sessions)
            ListTile(
              dense: true,
              leading: Icon(Icons.event_outlined, color: scheme.outline),
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
