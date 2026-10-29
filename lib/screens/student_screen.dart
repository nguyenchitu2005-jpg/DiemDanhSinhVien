import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';
import 'student_course_screen.dart';

/// Trang sinh viên: các lớp đã vào, tỉ lệ đi học, cảnh báo nguy cơ cấm thi, quét QR điểm danh
class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  late Future<dynamic> _history = Api.get('Attendance/history');

  Future<void> _reload() async {
    setState(() { _history = Api.get('Attendance/history'); });
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

  Future<void> _openCourse(Map course) async {
    final left = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StudentCourseScreen(course: course)));
    if (left == true) _reload();
  }

  /// Bảng trượt từ dưới lên khi bấm vào ô thống kê
  void _sheet(String title, List<Widget> children) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(title, style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...children,
      ]),
    ),
  );

  /// Mở trang lớp từ trong bảng trượt (đóng bảng trước)
  VoidCallback _fromSheet(Map course) => () {
    Navigator.pop(context);
    _openCourse(course);
  };

  void _showCourses(List courses) => _sheet('Lớp của tôi (${courses.length})', [
    if (courses.isEmpty) const Text('Bạn chưa vào lớp nào. Bấm biểu tượng thêm lớp ở góc trên để nhập mã.'),
    for (final c in courses)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const IconBox(Icons.menu_book_rounded),
        title: Text(c['name']),
        subtitle: Text('${c['code']} · Phòng ${c['room'] ?? '-'} · ${(c['sessions'] as List).length} buổi'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _fromSheet(c),
      ),
  ]);

  void _showAttendance(List courses) => _sheet('Chuyên cần từng lớp', [
    const Text('Vắng quá 20% số buổi đã học là nguy cơ cấm thi.'),
    const SizedBox(height: 8),
    for (final c in courses)
      Builder(builder: (context) {
        final int total = c['totalSessions'];
        final double rate = (c['absentRate'] as num).toDouble();
        final color = c['warning'] ? Theme.of(context).colorScheme.error : (rate >= 0.15 ? Colors.orange : Colors.green);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${c['code']} · ${c['name']}'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: total == 0 ? 0 : 1 - rate, color: color, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 4),
            Text(total == 0 ? 'Chưa có buổi nào' : 'Có mặt ${total - c['absent']}/$total buổi'),
          ]),
          trailing: Text(total == 0 ? '-' : '${((1 - rate) * 100).round()}%',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          onTap: _fromSheet(c),
        );
      }),
  ]);

  void _showAbsences(List courses) {
    final absences = [
      for (final c in courses)
        for (final s in c['sessions'] as List)
          if (s['status'] == 'Absent' || s['status'] == 'Excused') (course: c, session: s),
    ]..sort((a, b) => (b.session['startAt'] as String).compareTo(a.session['startAt']));
    _sheet('Buổi vắng (${absences.length})', [
      if (absences.isEmpty) const Text('Bạn chưa vắng buổi nào. Giữ vững nhé!'),
      for (final a in absences)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(a.session['status'] == 'Excused' ? Icons.assignment_turned_in : Icons.cancel,
              color: attendanceLabels[a.session['status']]!.$2, size: 32),
          title: Text('${a.course['code']} · ${a.session['title']}'),
          subtitle: Text('${a.course['name']}\n${fmtDate(a.session['startAt'], withYear: true)}'),
          isThreeLine: true,
          trailing: StatusChip(a.session['status']),
          onTap: _fromSheet(a.course),
        ),
    ]);
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
          final loaded = snap.hasData;
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
              Stat(Icons.class_outlined, '${courses.length}', 'Lớp', onTap: loaded ? () => _showCourses(courses) : null),
              Stat(Icons.verified_outlined, total == 0 ? '-' : '${((total - absent) * 100 / total).round()}%', 'Chuyên cần',
                  onTap: loaded ? () => _showAttendance(courses) : null),
              Stat(Icons.event_busy_outlined, '$absent', 'Buổi vắng', onTap: loaded ? () => _showAbsences(courses) : null),
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
                    onTap: () => _showAttendance(courses),
                  ),
                ),
              Text('Lớp của tôi', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final c in courses) _CourseCard(course: c, onTap: () => _openCourse(c)),
            ]);
          },
        ),
      ),
    ]),
  );
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onTap});
  final Map course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final int total = course['totalSessions'];
    final int absent = course['absent'];
    final double rate = (course['absentRate'] as num).toDouble();
    final bool warning = course['warning'];
    final color = warning ? scheme.error : (rate >= 0.15 ? Colors.orange : Colors.green);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        onTap: onTap,
        // Vòng tròn % chuyên cần của lớp
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: total == 0 ? 0 : 1 - rate,
                strokeWidth: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
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
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
