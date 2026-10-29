import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'course_screen.dart';
import 'profile_screen.dart';

/// Trang quản trị (Admin): CRUD tài khoản + phân quyền, CRUD lớp học + gán giảng viên
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      body: Column(
        children: [
          HomeHeader(
            subtitle: 'Trang quản trị',
            title: Auth.fullName,
            actions: [profileAction(context)],
            bottom: const TabBar(
              labelColor: kInk,
              unselectedLabelColor: Color(0x994A3712),
              indicatorColor: kInk,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'Tài khoản'),
                Tab(icon: Icon(Icons.class_outlined), text: 'Lớp học'),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [_UsersTab(), _CoursesTab()])),
        ],
      ),
    ),
  );
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

// Giữ trạng thái khi chuyển tab (không mất mục lọc, không tải lại)
class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _role;
  late Future<dynamic> _users = _load();

  Future<dynamic> _load() => Api.get(_role == null ? 'Users' : 'Users?role=$_role');

  Future<void> _reload() async {
    setState(() {
      _users = _load();
    }); // không dùng "=>": trả về Future thì setState báo lỗi và không vẽ lại
    await _users;
  }

  Future<void> _edit([Map? user]) async {
    final userName = TextEditingController(text: user?['userName']);
    final email = TextEditingController(text: user?['email']);
    final fullName = TextEditingController(text: user?['fullName']);
    final phone = TextEditingController(text: user?['phoneNumber']);
    final code = TextEditingController(text: user?['studentCode']);
    final password = TextEditingController();
    var role = user?['role'] ?? 'Student';
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(user == null ? 'Thêm tài khoản' : 'Sửa tài khoản'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Vai trò'),
                      items: [for (final e in roleLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setDialog(() => role = v!),
                    ),
                  ),
                  Field(fullName, 'Họ và tên', validator: notEmpty),
                  Field(userName, 'Tên đăng nhập', validator: notEmpty),
                  Field(email, 'Email', keyboard: TextInputType.emailAddress, validator: notEmpty),
                  Field(phone, 'Số điện thoại', keyboard: TextInputType.phone),
                  if (role == 'Student') Field(code, 'Mã sinh viên'),
                  Field(
                    password,
                    user == null ? 'Mật khẩu' : 'Mật khẩu mới (để trống: giữ nguyên)',
                    obscure: true,
                    validator: (v) => user != null && (v ?? '').isEmpty ? null : strongPassword(v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'userName': userName.text.trim(),
      'email': email.text.trim(),
      'fullName': fullName.text.trim(),
      'role': role,
      'phoneNumber': phone.text.trim(),
      'studentCode': code.text.trim(),
      'password': password.text,
    };
    final r = await guard(context, () => user == null ? Api.post('Users', body) : Api.put('Users/${user['id']}', body));
    if (r != null) _reload();
  }

  Future<void> _delete(Map user) async {
    if (!await confirm(context, 'Xoá tài khoản ${user['fullName']}? Dữ liệu điểm danh của tài khoản cũng bị xoá.') || !mounted) return;
    if (await guard(context, () => Api.delete('Users/${user['id']}')) != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addUser',
        onPressed: _edit,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Thêm'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                for (final (value, label) in [(null, 'Tất cả'), ...roleLabels.entries.map((e) => (e.key, e.value))])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _role == value,
                      onSelected: (_) {
                        _role = value;
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              future: _users,
              onRefresh: _reload,
              builder: (users) => users.isEmpty
                  ? const EmptyView('Chưa có tài khoản')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                            leading: Avatar(u['fullName'], color: roleColors[u['role']]),
                            title: Row(
                              children: [
                                Flexible(child: Text(u['fullName'], overflow: TextOverflow.ellipsis)),
                                if (u['hasFace'])
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Tooltip(
                                      message: 'Đã đăng ký khuôn mặt',
                                      child: Icon(Icons.face, size: 16, color: Colors.green),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${u['userName']}${u['studentCode'] != null ? ' · ${u['studentCode']}' : ''}\n${u['email'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                RoleChip(u['role']),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  onTap: () => _edit(u),
                                  child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa')),
                                ),
                                PopupMenuItem(
                                  onTap: () => _delete(u),
                                  child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Xoá')),
                                ),
                              ],
                            ),
                            onTap: () => _edit(u),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursesTab extends StatefulWidget {
  const _CoursesTab();

  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<dynamic> _courses = Api.get('Courses');

  Future<void> _reload() async {
    setState(() {
      _courses = Api.get('Courses');
    });
    await _courses;
  }

  Future<void> _edit([Map? course]) async {
    final teachers = await guard(context, () => Api.get('Users?role=Teacher'), showSuccess: false);
    if (teachers == null || !mounted) return;
    final code = TextEditingController(text: course?['code']);
    final name = TextEditingController(text: course?['name']);
    final room = TextEditingController(text: course?['room']);
    final radius = TextEditingController(text: '${course?['radiusM'] ?? 100}');
    String? teacherId = course?['teacherId'];
    final form = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(course == null ? 'Thêm lớp học' : 'Sửa lớp học'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(code, 'Mã lớp (VD: INT3120)', validator: notEmpty),
                Field(name, 'Tên học phần', validator: notEmpty),
                Field(room, 'Phòng học'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String?>(
                    initialValue: teacherId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Giảng viên'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('(Chưa gán)')),
                      for (final t in teachers) DropdownMenuItem(value: t['id'] as String, child: Text(t['fullName'])),
                    ],
                    onChanged: (v) => teacherId = v,
                  ),
                ),
                Field(
                  radius,
                  'Bán kính điểm danh (m)',
                  keyboard: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 10 ? 'Tối thiểu 10 m' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'code': code.text.trim(),
      'name': name.text.trim(),
      'room': room.text.trim(),
      'teacherId': teacherId,
      'radiusM': int.parse(radius.text),
      'latitude': course?['latitude'],
      'longitude': course?['longitude'],
    };
    final r = await guard(context, () => course == null ? Api.post('Courses', body) : Api.put('Courses/${course['id']}', body));
    if (r != null) _reload();
  }

  Future<void> _delete(Map course) async {
    if (!await confirm(context, 'Xoá lớp ${course['code']}? Mọi buổi học và dữ liệu điểm danh của lớp sẽ bị xoá.') || !mounted) return;
    if (await guard(context, () => Api.delete('Courses/${course['id']}')) != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addCourse',
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Thêm lớp'),
      ),
      body: AsyncView(
        future: _courses,
        onRefresh: _reload,
        builder: (courses) => courses.isEmpty
            ? const EmptyView('Chưa có lớp học', icon: Icons.class_outlined)
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: courses.length,
                itemBuilder: (_, i) {
                  final c = courses[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                      leading: const IconBox(Icons.menu_book_rounded),
                      title: Text('${c['code']} · ${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'GV: ${c['teacherName'] ?? '(chưa gán)'}\n'
                        'Phòng ${c['room'] ?? '-'} · ${c['studentCount']} SV · ${c['sessionCount']} buổi · Mã vào lớp ${c['joinCode']}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton(
                        itemBuilder: (_) => [
                          PopupMenuItem(onTap: () => _edit(c), child: const Text('Sửa')),
                          PopupMenuItem(onTap: () => _delete(c), child: const Text('Xoá')),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseScreen(course: c)));
                        _reload();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
