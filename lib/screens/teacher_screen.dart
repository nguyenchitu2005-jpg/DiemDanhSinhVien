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
    setState(() => _courses = Api.get('Courses'));
    await _courses;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Lớp của tôi'), actions: [profileAction(context)]),
      body: AsyncView(
        future: _courses,
        onRefresh: _reload,
        builder: (courses) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Xin chào, ${Auth.fullName}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Bạn đang dạy ${courses.length} lớp', style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 16),
          if (courses.isEmpty) const SizedBox(height: 300, child: EmptyView('Admin chưa gán lớp nào cho bạn')),
          for (final c in courses)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseScreen(course: c)));
                  _reload();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c['name'], style: Theme.of(context).textTheme.titleMedium)),
                      if (c['openSessionCount'] > 0)
                        const Chip(label: Text('Đang điểm danh'), avatar: Icon(Icons.circle, size: 10, color: Colors.green)),
                    ]),
                    Text('${c['code']} · Phòng ${c['room'] ?? '-'}', style: TextStyle(color: scheme.outline)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 16, runSpacing: 4, children: [
                      _Info(Icons.groups_outlined, '${c['studentCount']} sinh viên'),
                      _Info(Icons.event_note_outlined, '${c['sessionCount']} buổi'),
                      _Info(Icons.key_outlined, 'Mã lớp ${c['joinCode']}'),
                      _Info(c['latitude'] == null ? Icons.location_off_outlined : Icons.location_on_outlined,
                          c['latitude'] == null ? 'Chưa đặt vị trí' : 'Bán kính ${c['radiusM']} m'),
                    ]),
                  ]),
                ),
              ),
            ),
        ]),
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
