import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

const _statusIcons = {
  'Present': Icons.check_circle,
  'Late': Icons.schedule,
  'Excused': Icons.assignment_turned_in,
  'Absent': Icons.cancel,
  'Open': Icons.qr_code_scanner,
  'Upcoming': Icons.event_outlined,
};

/// Một lớp của sinh viên: tỉ lệ chuyên cần, số buổi theo trạng thái và từng buổi học (có mặt / muộn / có phép / vắng).
/// Trả về true khi sinh viên rời lớp để trang trước tải lại.
class StudentCourseScreen extends StatelessWidget {
  const StudentCourseScreen({super.key, required this.course});
  final Map course;

  Future<void> _leave(BuildContext context) async {
    if (!await confirm(context, 'Rời lớp ${course['code']}? Lịch sử điểm danh của lớp này sẽ bị xoá.') || !context.mounted) return;
    if (await guard(context, () => Api.delete('Courses/${course['id']}/leave')) != null && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final List sessions = course['sessions'];
    final int total = course['totalSessions'];
    final double rate = (course['absentRate'] as num).toDouble();
    final bool warning = course['warning'];
    final color = warning ? scheme.error : (rate >= 0.15 ? Colors.orange : Colors.green);
    int count(String status) => sessions.where((s) => s['status'] == status).length;

    return Scaffold(
      appBar: AppBar(title: Text(course['code'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : 1 - rate,
                        strokeWidth: 8,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(total == 0 ? '-' : '${((1 - rate) * 100).round()}%',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Text('chuyên cần', style: TextStyle(fontSize: 10)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(course['name'], style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${course['code']} · Phòng ${course['room'] ?? '-'}', style: TextStyle(color: scheme.outline)),
                    const SizedBox(height: 4),
                    Text(total == 0 ? 'Chưa có buổi nào được điểm danh' : 'Đã học $total buổi · vắng ${course['absent']} buổi'),
                    if (count('Upcoming') > 0) Text('Còn ${count('Upcoming')} buổi theo lịch', style: TextStyle(color: scheme.outline)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                for (final status in ['Present', 'Late', 'Excused', 'Absent'])
                  Expanded(
                    child: Column(children: [
                      Text('${count(status)}',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: attendanceLabels[status]!.$2.shade700)),
                      Text(attendanceLabels[status]!.$1, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
              ]),
              if (warning) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(width: 8),
                    Expanded(child: Text('Vắng quá 20% số buổi – nguy cơ cấm thi')),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('Các buổi học (${sessions.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text('Lớp chưa có lịch học', textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
          ),
        for (final s in sessions)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_statusIcons[s['status']] ?? Icons.help_outline, color: attendanceLabels[s['status']]?.$2, size: 32),
              title: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                fmtDate(s['startAt'], withYear: true),
                if (s['checkedAt'] != null) 'điểm danh lúc ${fmtDate(s['checkedAt'])}',
                if (s['status'] == 'Open') 'đang điểm danh – hãy quét QR ngay',
              ].join(' · ')),
              trailing: StatusChip(s['status']),
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(onPressed: () => _leave(context), icon: const Icon(Icons.logout), label: const Text('Rời lớp')),
        ),
      ]),
    );
  }
}
