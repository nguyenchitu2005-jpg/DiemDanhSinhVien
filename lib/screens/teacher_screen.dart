import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'course_screen.dart';
import 'profile_screen.dart';

/// Dashboard giảng viên: các lớp mình dạy
class TeacherScreen extends StatefulWidget {
  const TeacherScreen({super.key});

  @override
  State<TeacherScreen> createState() => _TeacherScreenState();
}

class _TeacherScreenState extends State<TeacherScreen> {
  late Future<dynamic> _courses = Api.get('Courses');

  Future<void> _reload() async {
    setState(() { _courses = Api.get('Courses'); });
    await _courses;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      // Đầu trang ngoài AsyncView: lỗi mạng vẫn bấm được nút hồ sơ để đăng xuất
      FutureBuilder(
        future: _courses,
        builder: (_, snap) {
          final List courses = snap.data ?? [];
          int sum(String key) => courses.fold(0, (s, c) => s + (c[key] as int));
          return HomeHeader(
            subtitle: 'Giảng viên',
            title: Auth.fullName,
            actions: [profileAction(context)],
            stats: [
              Stat(Icons.class_outlined, '${courses.length}', 'Lớp'),
              Stat(Icons.event_note_outlined, '${sum('sessionCount')}', 'Buổi học'),
              Stat(Icons.qr_code_2, '${sum('openSessionCount')}', 'Đang mở'),
            ],
          );
        },
      ),
      Expanded(
        child: AsyncView(
          future: _courses,
          onRefresh: _reload,
          builder: (courses) => courses.isEmpty
              ? const EmptyView('Admin chưa gán lớp nào cho bạn', icon: Icons.class_outlined)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Lớp của tôi', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final c in courses) _CourseCard(course: c, onBack: _reload),
                ]),
        ),
      ),
    ]),
  );
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onBack});
  final Map course;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = course;
    final scheme = Theme.of(context).colorScheme;
    final open = c['openSessionCount'] > 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseScreen(course: c)));
          onBack();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBox(Icons.menu_book_rounded, color: open ? Colors.green : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name'], style: Theme.of(context).textTheme.titleMedium),
                  Text('${c['code']} · Phòng ${c['room'] ?? '-'}', style: TextStyle(color: scheme.outline)),
                ]),
              ),
              if (open) const StatusChip('Open'),
              Icon(Icons.chevron_right, color: scheme.outline),
            ]),
            const Divider(height: 24),
            Wrap(spacing: 16, runSpacing: 6, children: [
              _Info(Icons.groups_outlined, '${c['studentCount']} SV'),
              _Info(Icons.event_note_outlined, '${c['sessionCount']} buổi'),
              _Info(Icons.key_outlined, c['joinCode']),
              _Info(c['latitude'] == null ? Icons.location_off_outlined : Icons.location_on_outlined,
                  c['latitude'] == null ? 'Chưa đặt vị trí' : '${c['radiusM']} m'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 4),
    Text(text),
  ]);
}
