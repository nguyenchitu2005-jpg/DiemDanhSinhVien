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
    setState(() { _sessions = _loadSessions(); });
    await _sessions.catchError((_) => null); // lỗi đã hiện trong AsyncView
  }

  Future<void> _reloadStudents() async {
    setState(() { _students = _loadStudents(); });
    await _students.catchError((_) => null); // lỗi đã hiện trong AsyncView
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

  bool get _isAdmin => Auth.role == 'Admin';

  /// Admin tạo lịch: [số buổi] buổi, buổi đầu lúc [ngày giờ], lặp lại mỗi [n] ngày
  Future<void> _createSchedule() async {
    var first = DateTime.now().copyWith(hour: 7, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final count = TextEditingController(text: '15');
    final every = TextEditingController(text: '7');
    final lateMin = TextEditingController(text: '15');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Tạo lịch học'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Buổi đầu tiên'),
                subtitle: Text(fmtSchedule(first.toUtc().toIso8601String())),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final picked = await pickDateTime(c, first);
                  if (picked != null) setDialog(() => first = picked);
                },
              ),
              Field(count, 'Số buổi', keyboard: TextInputType.number),
              Field(every, 'Lặp lại mỗi (ngày) – 7 = mỗi tuần', keyboard: TextInputType.number),
              Field(lateMin, 'Sau bao nhiêu phút tính đi muộn', keyboard: TextInputType.number),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tạo lịch')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.post('courses/${_course['id']}/schedule', {
      'firstStartAt': first.toUtc().toIso8601String(),
      'count': int.tryParse(count.text) ?? 1,
      'everyDays': int.tryParse(every.text) ?? 7,
      'lateAfterMin': int.tryParse(lateMin.text) ?? 15,
    }));
    if (r != null) _reloadSessions();
  }

  /// Admin sửa tên / ngày giờ / phút tính muộn của 1 buổi
  Future<void> _editSession(Map session) async {
    final title = TextEditingController(text: session['title']);
    final lateMin = TextEditingController(text: '${session['lateAfterMin']}');
    var startAt = DateTime.parse(session['startAt']).toLocal();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Sửa buổi học'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Field(title, 'Tên buổi'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Ngày giờ học'),
              subtitle: Text(fmtSchedule(startAt.toUtc().toIso8601String())),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final picked = await pickDateTime(c, startAt);
                if (picked != null) setDialog(() => startAt = picked);
              },
            ),
            Field(lateMin, 'Sau bao nhiêu phút tính đi muộn', keyboard: TextInputType.number),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await guard(context, () => Api.put('sessions/${session['id']}', {
      'title': title.text.trim(),
      'startAt': startAt.toUtc().toIso8601String(),
      'lateAfterMin': int.tryParse(lateMin.text) ?? 15,
    }));
    if (r != null) _reloadSessions();
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

  /// Lịch các buổi học: Admin tạo / sửa / xoá; giảng viên chọn buổi để điểm danh
  Widget _sessionsTab() => AsyncView(
    future: _sessions,
    onRefresh: _reloadSessions,
    builder: (sessions) => Scaffold(
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(onPressed: _createSchedule, icon: const Icon(Icons.edit_calendar), label: const Text('Tạo lịch học'))
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        if (_course['latitude'] == null)
          Card(
            color: kCream,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Chưa đặt vị trí phòng học'),
              subtitle: const Text('Sinh viên ở đâu cũng điểm danh được. Bấm để chọn vị trí phòng trên bản đồ.'),
              onTap: _setLocation,
            ),
          ),
        if (!_isAdmin && sessions.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('Chọn buổi học để điểm danh'),
          ),
        if (sessions.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyView(_isAdmin ? 'Chưa có lịch học. Bấm "Tạo lịch học" để thêm các buổi.' : 'Admin chưa tạo lịch học cho lớp này',
                icon: Icons.event_note),
          ),
        for (final s in sessions) _sessionCard(s),
      ]),
    ),
  );

  Widget _sessionCard(Map s) {
    final open = s['isOpen'] == true;
    final held = s['startedAt'] != null;
    final (icon, color, statusText) = open
        ? (Icons.qr_code_2, Colors.teal, 'Đang điểm danh…')
        : held
            ? (Icons.fact_check_outlined, Colors.green, 'Đã điểm danh: ${s['presentCount']}/${s['total']} SV')
            : (Icons.event_outlined, Colors.blueGrey, 'Chưa điểm danh');
    final today = isToday(s['startAt']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: today ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: kGold, width: 2)) : null,
      child: ListTile(
        leading: IconBox(icon, color: color),
        title: Row(children: [
          Flexible(child: Text(s['title'], style: const TextStyle(fontWeight: FontWeight.w600))),
          if (today)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: kCreamDeep, borderRadius: BorderRadius.circular(10)),
              child: const Text('Hôm nay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kInk)),
            ),
        ]),
        subtitle: Text('${fmtSchedule(s['startAt'])}\n$statusText'),
        isThreeLine: true,
        trailing: _isAdmin
            ? PopupMenuButton(
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
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _open(s['id']),
      ),
    );
  }

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
