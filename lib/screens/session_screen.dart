import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../map.dart';
import '../widgets.dart';

/// Một buổi học: giảng viên bắt đầu điểm danh 1 phút (QR đổi mỗi 15 giây), hết giờ tự dừng và lưu danh sách;
/// điểm danh tay cho SV chưa quét được, xuất Excel, bản đồ vị trí sinh viên
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});
  final int sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map? _data; // {session, students}
  String? _error;
  String? _qr;
  int _qrRemain = 0; // giây còn lại của mã QR hiện tại
  int _window = 0; // giây còn nhận điểm danh (đếm lùi trên máy, đồng bộ lại với server mỗi lần tải)
  int _tick = 0;
  bool _busy = false;
  Timer? _timer;

  Map get _session => _data!['session'];
  List get _students => _data!['students'];
  bool get _open => _window > 0;
  int _count(String status) => _students.where((s) => s['status'] == status).length;

  @override
  void initState() {
    super.initState();
    _load().then((_) => _refreshQr());
    // Chỉ chạy khi đang điểm danh: đếm lùi, đổi mã QR, 5 giây tải lại danh sách; hết giờ thì chốt danh sách
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _data == null || !_open) return;
      setState(() {
        _window--;
        _qrRemain--;
      });
      if (_window <= 0) {
        _finish();
        return;
      }
      if (_qrRemain <= 0) _refreshQr();
      if (++_tick % 5 == 0) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('sessions/${widget.sessionId}/attendances');
      if (!mounted) return;
      setState(() {
        _data = data;
        _window = data['session']['remainingSeconds'];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _fetchingQr = false;

  Future<void> _refreshQr() async {
    if (_fetchingQr || _data == null || !_open) return;
    _fetchingQr = true;
    try {
      final r = await Api.get('sessions/${widget.sessionId}/qr');
      if (!mounted) return;
      setState(() {
        _qr = r['content'];
        _qrRemain = r['expiresInSeconds'];
      });
    } catch (_) {
      // lỗi mạng thoáng qua: giây sau thử lại
    } finally {
      _fetchingQr = false;
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final r = await guard(context, () => Api.post('sessions/${widget.sessionId}/start'), showSuccess: false);
    if (r != null) {
      await _load();
      await _refreshQr();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stop() async {
    if (await guard(context, () => Api.post('sessions/${widget.sessionId}/stop'), showSuccess: false) != null) _finish();
  }

  /// Hết 1 phút (hoặc bấm dừng): tải danh sách đã lưu trên server và báo sĩ số
  Future<void> _finish() async {
    setState(() => _window = 0);
    await _load();
    if (!mounted || _data == null) return;
    showMsg(context, 'Đã kết thúc điểm danh: ${_count('Present') + _count('Late')}/${_students.length} sinh viên có mặt. Danh sách đã được lưu.');
  }

  /// Điểm danh tay: đổi ngay trên màn hình, lỗi thì trả lại trạng thái cũ
  Future<void> _mark(Map student, String status) async {
    final old = student['status'];
    if (status == old) return;
    setState(() => student['status'] = status);
    final path = 'sessions/${widget.sessionId}/attendances/${student['studentId']}';
    final r = await guard(context, () => status == 'Absent' ? Api.delete(path) : Api.put(path, {'status': status}), showSuccess: false);
    if (r == null && mounted) setState(() => student['status'] = old);
  }

  Future<void> _setStatus(Map student) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(student['fullName'], style: Theme.of(context).textTheme.titleMedium)),
          for (final k in _manualStatuses)
            ListTile(
              leading: Icon(Icons.circle, color: attendanceLabels[k]!.$2),
              title: Text(attendanceLabels[k]!.$1),
              selected: student['status'] == k,
              onTap: () => Navigator.pop(c, k),
            ),
        ]),
      ),
    );
    if (status != null && mounted) _mark(student, status);
  }

  /// Tải file Excel do server tạo rồi mở bảng chia sẻ (lưu vào Files / Drive, gửi Zalo, email…)
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bytes = await Api.download('sessions/${widget.sessionId}/export');
      final d = DateTime.parse(_session['startAt']).toLocal();
      final name = 'DiemDanh_${_session['courseCode']}_${d.day}-${d.month}-${d.year}.xlsx';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        fileNameOverrides: [name],
        subject: 'Điểm danh ${_session['courseCode']} – ${_session['title']}',
      ));
    } catch (e) {
      if (mounted) showMsg(context, e is ApiException ? e.message : 'Không xuất được file: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  static const _manualStatuses = ['Present', 'Late', 'Excused', 'Absent'];

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
      );
    }
    final present = _count('Present') + _count('Late');
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_session['title']} · ${_session['courseCode']}', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Xuất Excel', onPressed: _busy ? null : _export, icon: const Icon(Icons.file_download_outlined)),
          ],
          bottom: TabBar(tabs: [
            const Tab(icon: Icon(Icons.qr_code_2), text: 'Điểm danh'),
            Tab(icon: const Icon(Icons.checklist), text: 'Danh sách $present/${_students.length}'),
            const Tab(icon: Icon(Icons.map_outlined), text: 'Bản đồ'),
          ]),
        ),
        body: TabBarView(children: [_attendanceTab(), _listTab(), _mapTab()]),
      ),
    );
  }

  /// Sĩ số + số có mặt / muộn / có phép / vắng
  Widget _counts() => Row(children: [
    for (final (label, value, color) in [
      ('Sĩ số', _students.length, kInk),
      ('Có mặt', _count('Present'), Colors.green.shade700),
      ('Đi muộn', _count('Late'), Colors.orange.shade700),
      ('Có phép', _count('Excused'), Colors.blue.shade700),
      ('Vắng', _count('Absent'), Colors.red.shade700),
    ])
      Expanded(
        child: Column(children: [
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      ),
  ]);

  Widget _attendanceTab() {
    final total = _students.length;
    final present = _count('Present') + _count('Late');
    if (_open) {
      final int windowSeconds = _session['windowSeconds'];
      return ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: kBrandGradient, borderRadius: BorderRadius.circular(28)),
          child: Column(children: [
            const Text('Mở app → "Quét QR điểm danh"', style: TextStyle(color: kInk, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: _qr == null
                  ? const SizedBox(width: 240, height: 240, child: Center(child: CircularProgressIndicator()))
                  : QrImageView(data: _qr!, size: 240, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _window.clamp(0, windowSeconds) / windowSeconds,
                      strokeWidth: 5,
                      color: kInk,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  Text('$_window', style: const TextStyle(color: kInk, fontWeight: FontWeight.bold, fontSize: 18)),
                ]),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text('giây còn lại để điểm danh\nMã QR tự đổi sau $_qrRemain giây',
                    style: const TextStyle(color: kInk)),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const IconBox(Icons.how_to_reg, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$present / $total', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Text('sinh viên đã điểm danh'),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Dừng điểm danh')),
      ]);
    }

    // Chưa điểm danh hoặc đã kết thúc: thông tin buổi, sĩ số đã lưu, bắt đầu / điểm danh thêm, xuất Excel
    final held = _session['startedAt'] != null;
    final notChecked = _count('Absent');
    return ListView(padding: const EdgeInsets.all(20), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_session['title'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text('${_session['courseName']}\n${fmtSchedule(_session['startAt'])}'),
            const Divider(height: 24),
            if (!held)
              const Text('Buổi học chưa điểm danh. Bấm "Bắt đầu điểm danh", sinh viên có 1 phút để quét mã QR.')
            else ...[
              const Text('Danh sách điểm danh đã lưu', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _counts(),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _start,
        icon: const Icon(Icons.qr_code_2),
        label: Text(held ? 'Điểm danh thêm 1 phút' : 'Bắt đầu điểm danh (1 phút)'),
      ),
      if (held) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Xuất Excel'),
        ),
        if (notChecked > 0)
          Builder(
            builder: (c) => Card(
              margin: const EdgeInsets.only(top: 16),
              color: kCream,
              child: ListTile(
                leading: const Icon(Icons.edit_note, color: kInk),
                title: Text('$notChecked sinh viên chưa điểm danh'),
                subtitle: const Text('Bấm để chọn Có mặt / Đi muộn / Có phép / Vắng cho từng bạn'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => DefaultTabController.of(c).animateTo(1),
              ),
            ),
          ),
      ],
    ]);
  }

  /// Danh sách sinh viên: chọn nhanh trạng thái cho từng bạn (dùng cho SV chưa quét được QR)
  Widget _listTab() => _students.isEmpty
      ? const EmptyView('Lớp chưa có sinh viên')
      : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
          Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _counts())),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text('Chọn trạng thái cho sinh viên chưa quét được QR – lưu ngay khi bấm'),
          ),
          for (final s in _students)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Avatar(s['fullName'], color: attendanceLabels[s['status']]?.$2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['fullName'], style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            s['studentCode'],
                            if (s['checkedAt'] != null) fmtDate(s['checkedAt']),
                            if (s['distanceM'] != null) 'cách ${(s['distanceM'] as num).toStringAsFixed(0)} m',
                            if (s['method'] == 'Manual') 'điểm danh tay',
                          ].whereType<String>().join(' · '),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        selectedBackgroundColor: (attendanceLabels[s['status']]?.$2 ?? Colors.grey).withValues(alpha: 0.18),
                        selectedForegroundColor: (attendanceLabels[s['status']]?.$2 ?? Colors.grey).shade800,
                      ),
                      segments: [
                        for (final k in _manualStatuses)
                          ButtonSegment(value: k, label: Text(attendanceLabels[k]!.$1, style: const TextStyle(fontSize: 12))),
                      ],
                      selected: {s['status']},
                      onSelectionChanged: (v) => _mark(s, v.first),
                    ),
                  ),
                ]),
              ),
            ),
        ]);

  /// Bản đồ: vòng bán kính phòng học, ghim phòng, vị trí từng SV (màu theo trạng thái) nối nét đứt về phòng,
  /// chạm vào SV để xem chi tiết; chú thích số SV trong / ngoài vùng ở dưới
  Widget _mapTab() {
    final lat = _session['latitude'];
    final lng = _session['longitude'];
    final located = _students.where((s) => s['latitude'] != null).toList();
    if (lat == null && located.isEmpty) {
      return const EmptyView('Chưa có vị trí phòng học và chưa có sinh viên điểm danh', icon: Icons.location_off_outlined);
    }
    final room = lat == null ? null : LatLng(lat, lng);
    LatLng pos(dynamic s) => LatLng(s['latitude'], s['longitude']);
    final num radius = _session['radiusM'];
    final inside = located.where((s) => s['distanceM'] != null && s['distanceM'] <= radius).length;
    final noLocation = _students.where((s) => s['status'] != 'Absent' && s['latitude'] == null).length;

    return Stack(children: [
      AppMap(
        center: room ?? pos(located.first),
        fitPoints: [?room, ...located.map(pos)],
        layers: [
          if (room != null) roomCircle(room, radius),
          if (room != null)
            PolylineLayer(polylines: [
              for (final s in located)
                Polyline(
                  points: [room, pos(s)],
                  color: (attendanceLabels[s['status']]?.$2 ?? Colors.grey).withValues(alpha: 0.8),
                  strokeWidth: 2,
                  pattern: StrokePattern.dashed(segments: const [8, 6]),
                ),
            ]),
          MarkerLayer(markers: [
            if (room != null) roomMarker(room),
            for (final s in located)
              Marker(
                point: pos(s),
                width: 110,
                height: 64,
                alignment: Alignment.bottomCenter, // tâm chấm tròn nằm đúng toạ độ
                child: GestureDetector(
                  onTap: () => _studentSheet(s),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: attendanceLabels[s['status']]?.$2 ?? Colors.grey,
                        child: Text(initials(s['fullName']), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '${s['fullName'].toString().split(' ').last}'
                        '${s['distanceM'] != null ? ' · ${(s['distanceM'] as num).toStringAsFixed(0)} m' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kInk),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ],
      ),
      // Chú thích
      Positioned(
        left: 12,
        right: 72,
        bottom: 28,
        child: Card(
          color: Colors.white,
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(room == null ? 'Lớp chưa đặt vị trí phòng học' : 'Bán kính cho phép: $radius m',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: kInk)),
              const SizedBox(height: 4),
              Text('Trong vùng: $inside · Ngoài vùng: ${located.length - inside}'
                  '${noLocation > 0 ? ' · Điểm danh tay: $noLocation' : ''}'),
              const SizedBox(height: 6),
              Wrap(spacing: 12, children: [
                for (final k in ['Present', 'Late'])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 12, color: attendanceLabels[k]!.$2),
                    const SizedBox(width: 4),
                    Text(attendanceLabels[k]!.$1, style: const TextStyle(fontSize: 12)),
                  ]),
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.location_on, size: 14, color: Color(0xFFC62828)),
                  SizedBox(width: 2),
                  Text('Phòng học', style: TextStyle(fontSize: 12)),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }

  void _studentSheet(Map s) {
    final num? d = s['distanceM'];
    final num radius = _session['radiusM'];
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Avatar(s['fullName'], color: attendanceLabels[s['status']]?.$2),
              title: Text(s['fullName'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(s['studentCode'] ?? ''),
              trailing: StatusChip(s['status']),
            ),
            ListTile(leading: const Icon(Icons.schedule), title: Text('Điểm danh lúc ${fmtDate(s['checkedAt'], withYear: true)}')),
            if (d != null)
              ListTile(
                leading: Icon(d <= radius ? Icons.verified : Icons.warning_amber, color: d <= radius ? Colors.green : Colors.orange),
                title: Text('Cách phòng học ${d.toStringAsFixed(0)} m'),
                subtitle: Text(d <= radius ? 'Trong bán kính $radius m' : 'Ngoài bán kính $radius m'),
              ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text('${(s['latitude'] as num).toStringAsFixed(6)}, ${(s['longitude'] as num).toStringAsFixed(6)}'),
              subtitle: const Text('Toạ độ GPS lúc điểm danh'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(c);
                _setStatus(s);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Sửa trạng thái'),
            ),
          ]),
        ),
      ),
    );
  }
}
