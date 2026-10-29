import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../map.dart';
import '../widgets.dart';

/// Một buổi học: QR động (đổi mỗi 15 giây), danh sách điểm danh cập nhật liên tục, bản đồ vị trí sinh viên
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
  int _remain = 0; // giây còn lại của mã QR hiện tại
  int _tick = 0;
  Timer? _timer;

  Map get _session => _data!['session'];
  List get _students => _data!['students'];

  @override
  void initState() {
    super.initState();
    _load().then((_) => _refreshQr());
    // 1 timer: mỗi giây đếm ngược QR; hết hạn thì lấy mã mới; 5 giây tải lại danh sách 1 lần
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _data == null) return;
      setState(() => _remain--);
      if (_remain <= 0 && _session['isOpen'] == true) _refreshQr();
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
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _fetchingQr = false;

  Future<void> _refreshQr() async {
    if (_fetchingQr || _data == null || _session['isOpen'] != true) return;
    _fetchingQr = true;
    try {
      final r = await Api.get('sessions/${widget.sessionId}/qr');
      if (!mounted) return;
      setState(() {
        _qr = r['content'];
        _remain = r['expiresInSeconds'];
      });
    } catch (_) {
      // lỗi mạng thoáng qua: giây sau thử lại
    } finally {
      _fetchingQr = false;
    }
  }

  Future<void> _toggleOpen() async {
    final open = !(_session['isOpen'] as bool);
    final r = await guard(context, () => Api.put('sessions/${widget.sessionId}', {
      'title': _session['title'],
      'startAt': _session['startAt'],
      'lateAfterMin': _session['lateAfterMin'],
      'isOpen': open,
    }));
    if (r == null) return;
    await _load();
    if (open) _refreshQr();
  }

  Future<void> _setStatus(Map student) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(student['fullName'], style: Theme.of(context).textTheme.titleMedium)),
          for (final e in attendanceLabels.entries.where((e) => e.key != 'Open'))
            ListTile(
              leading: Icon(Icons.circle, color: e.value.$2),
              title: Text(e.value.$1),
              selected: student['status'] == e.key,
              onTap: () => Navigator.pop(c, e.key),
            ),
        ]),
      ),
    );
    if (status == null || status == student['status'] || !mounted) return;
    final path = 'sessions/${widget.sessionId}/attendances/${student['studentId']}';
    final r = await guard(context, () => status == 'Absent' ? Api.delete(path) : Api.put(path, {'status': status}));
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)),
      );
    }
    final open = _session['isOpen'] == true;
    final present = _students.where((s) => s['status'] != 'Absent' && s['status'] != 'Excused').length;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_session['title']} · ${_session['courseName']}', overflow: TextOverflow.ellipsis),
          actions: [
            TextButton.icon(
              onPressed: _toggleOpen,
              icon: Icon(open ? Icons.lock_outline : Icons.lock_open),
              label: Text(open ? 'Đóng' : 'Mở lại'),
            ),
          ],
          bottom: TabBar(tabs: [
            const Tab(icon: Icon(Icons.qr_code_2), text: 'Mã QR'),
            Tab(icon: const Icon(Icons.checklist), text: 'Danh sách $present/${_students.length}'),
            const Tab(icon: Icon(Icons.map_outlined), text: 'Bản đồ'),
          ]),
        ),
        body: TabBarView(children: [_qrTab(open, present), _listTab(), _mapTab()]),
      ),
    );
  }

  Widget _qrTab(bool open, int present) {
    final scheme = Theme.of(context).colorScheme;
    if (!open) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 64, color: scheme.outline),
          const SizedBox(height: 12),
          const Text('Buổi học đã đóng điểm danh'),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _toggleOpen, child: const Text('Mở lại điểm danh')),
        ]),
      );
    }
    final total = _students.length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      // QR trong khung gradient cho nổi bật khi chiếu lên màn hình lớp
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
                ? const SizedBox(width: 260, height: 260, child: Center(child: CircularProgressIndicator()))
                : QrImageView(data: _qr!, size: 260, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: _remain.clamp(0, 15) / 15,
                  strokeWidth: 4,
                  color: kInk,
                  backgroundColor: Colors.white,
                ),
                Text('$_remain', style: const TextStyle(color: kInk, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('giây nữa mã tự đổi – ảnh chụp gửi bạn sẽ không dùng được',
                  style: TextStyle(color: kInk)),
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
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                value: total == 0 ? 0 : present / total,
                strokeWidth: 6,
                color: Colors.green,
                backgroundColor: Colors.green.withValues(alpha: 0.15),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _listTab() => _students.isEmpty
      ? const EmptyView('Lớp chưa có sinh viên')
      : ListView.separated(
          itemCount: _students.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = _students[i];
            final info = [
              s['studentCode'],
              if (s['checkedAt'] != null) fmtDate(s['checkedAt']),
              if (s['distanceM'] != null) 'cách ${(s['distanceM'] as num).toStringAsFixed(0)} m',
              if (s['method'] == 'Manual') 'điểm danh tay',
            ].whereType<String>().join(' · ');
            return ListTile(
              leading: Avatar(s['fullName'], color: attendanceLabels[s['status']]?.$2),
              title: Text(s['fullName']),
              subtitle: Text(info),
              trailing: StatusChip(s['status']),
              onTap: () => _setStatus(s),
            );
          },
        );

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
