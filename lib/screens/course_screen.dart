import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../widgets.dart';
import 'location_picker.dart';
import 'session_screen.dart';

/// Một lớp (giảng viên/Admin): CRUD buổi học, danh sách sinh viên, đặt vị trí phòng học
class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key, required this.course});
  final Map course;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late final Map _course = Map.of(widget.course);
  late Future<dynamic> _sessions = _loadSessions();
  late Future<dynamic> _students = _loadStudents();

  Future<dynamic> _loadSessions() => Api.get('courses/${_course['id']}/sessions');
  Future<dynamic> _loadStudents() => Api.get('Courses/${_course['id']}/students');

  Future<void> _reloadSessions() async {
    setState(() => _sessions = _loadSessions());
    await _sessions;
  }

  Future<void> _reloadStudents() async {
    setState(() => _students = _loadStudents());
    await _students;
  }

  /// Chọn vị trí phòng học trên bản đồ (mặc định là GPS hiện tại của giảng viên) + bán kính điểm danh
  Future<void> _setLocation() async {
    final lat = _course['latitude'];
    final picked = await Navigator.of(context).push<(LatLng, int)>(MaterialPageRoute(
      builder: (_) => LocationPicker(initial: lat == null ? null : LatLng(lat, _course['longitude']), radiusM: _course['radiusM']),
    ));
    if (picked == null || !mounted) return;
    final (point, radius) = picked;
    final body = {
      'code': _course['code'],
      'name': _course['name'],
      'room': _course['room'],
      'teacherId': _course['teacherId'],
      'latitude': point.latitude,
      'longitude': point.longitude,
      'radiusM': radius,
    };
    if (await guard(context, () => Api.put('Courses/${_course['id']}', body)) != null) {
      setState(() => _course.addAll(body));
    }
  }

  Future<void> _editSession([Map? session, int count = 0]) async {
    final title = TextEditingController(text: session?['title'] ?? 'Buổi ${count + 1}');
    final lateMin = TextEditingController(text: '${session?['lateAfterMin'] ?? 15}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(session == null ? 'Tạo buổi học' : 'Sửa buổi học'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Field(title, 'Tên buổi'),
          Field(lateMin, 'Sau bao nhiêu phút tính là đi muộn', keyboard: TextInputType.number),
          if (session == null) const Text('Buổi học bắt đầu từ bây giờ và mở điểm danh ngay.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(session == null ? 'Tạo & mở QR' : 'Lưu')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'title': title.text.trim(),
      'lateAfterMin': int.tryParse(lateMin.text) ?? 15,
      'isOpen': session?['isOpen'] ?? true,
      'startAt': session?['startAt'],
    };
    final r = await guard(context,
        () => session == null ? Api.post('courses/${_course['id']}/sessions', body) : Api.put('sessions/${session['id']}', body));
    if (r == null || !mounted) return;
    if (session == null) await _open(r['id']);
    _reloadSessions();
  }

  Future<void> _open(int sessionId) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(sessionId: sessionId)));
    _reloadSessions();
    _reloadStudents();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_course['code']),
        actions: [
          IconButton(
            tooltip: 'Đặt vị trí phòng học',
            icon: Icon(_course['latitude'] == null ? Icons.location_off_outlined : Icons.my_location),
            onPressed: _setLocation,
          ),
        ],
        bottom: const TabBar(tabs: [Tab(text: 'Buổi học'), Tab(text: 'Sinh viên')]),
      ),
      body: TabBarView(children: [_sessionsTab(), _studentsTab()]),
    ),
  );

  Widget _sessionsTab() => AsyncView(
    future: _sessions,
    onRefresh: _reloadSessions,
    builder: (sessions) => Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSession(null, sessions.length),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Tạo buổi'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        if (_course['latitude'] == null)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Chưa đặt vị trí phòng học'),
              subtitle: const Text('Sinh viên ở đâu cũng điểm danh được. Bấm để chọn vị trí phòng trên bản đồ.'),
              onTap: _setLocation,
            ),
          ),
        if (sessions.isEmpty) const SizedBox(height: 300, child: EmptyView('Chưa có buổi học nào', icon: Icons.event_note)),
        for (final s in sessions)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: s['isOpen'] ? Colors.green.shade100 : null,
                child: Icon(s['isOpen'] ? Icons.qr_code_2 : Icons.lock_outline, color: s['isOpen'] ? Colors.green.shade800 : null),
              ),
              title: Text(s['title']),
              subtitle: Text('${fmtDate(s['startAt'], withYear: true)} · Có mặt ${s['presentCount']}/${s['total']}'),
              trailing: PopupMenuButton(
                itemBuilder: (_) => [
                  PopupMenuItem(onTap: () => _editSession(s), child: const Text('Sửa')),
                  PopupMenuItem(
                    onTap: () async {
                      if (!await confirm(context, 'Xoá ${s['title']} và dữ liệu điểm danh của buổi này?') || !mounted) return;
                      if (await guard(context, () => Api.delete('sessions/${s['id']}')) != null) _reloadSessions();
                    },
                    child: const Text('Xoá'),
                  ),
                ],
              ),
              onTap: () => _open(s['id']),
            ),
          ),
      ]),
    ),
  );

  Widget _studentsTab() => AsyncView(
    future: _students,
    onRefresh: _reloadStudents,
    builder: (data) {
      final List students = data['students'];
      final int total = data['sessionCount'];
      final scheme = Theme.of(context).colorScheme;
      return ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: scheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.key),
            title: Text('Mã vào lớp: ${_course['joinCode']}', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
            subtitle: Text('${students.length} sinh viên · Gửi mã này để sinh viên tự vào lớp'),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _course['joinCode']));
                showMsg(context, 'Đã chép mã lớp');
              },
            ),
          ),
        ),
        for (final s in students)
          ListTile(
            leading: Avatar(s['fullName'], color: s['atRisk'] ? scheme.error : null),
            title: Text(s['fullName']),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['studentCode'] ?? s['email'] ?? ''} · Có mặt ${s['attended']}/$total buổi'),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: total == 0 ? 0 : s['attended'] / total,
                color: s['atRisk'] ? scheme.error : Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              if (s['atRisk'])
                Text('Nguy cơ cấm thi (vắng > 20%)', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
            ]),
            trailing: IconButton(
              tooltip: 'Xoá khỏi lớp',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () async {
                if (!await confirm(context, 'Xoá ${s['fullName']} khỏi lớp?') || !mounted) return;
                if (await guard(context, () => Api.delete('Courses/${_course['id']}/students/${s['studentId']}')) != null) {
                  _reloadStudents();
                }
              },
            ),
          ),
      ]);
    },
  );
}
