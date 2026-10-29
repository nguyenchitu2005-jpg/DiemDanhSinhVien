import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
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
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Sinh viên mở app → "Quét QR điểm danh"', textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
      const SizedBox(height: 16),
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: _qr == null
              ? const SizedBox(width: 280, height: 280, child: Center(child: CircularProgressIndicator()))
              : QrImageView(data: _qr!, size: 280, backgroundColor: Colors.white),
        ),
      ),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: (_remain.clamp(0, 15)) / 15, borderRadius: BorderRadius.circular(4)),
      const SizedBox(height: 8),
      Text('Mã tự đổi sau $_remain giây – ảnh chụp mã gửi cho bạn sẽ không dùng được',
          textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
      const SizedBox(height: 24),
      Text('$present / ${_students.length}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
      const Text('sinh viên đã điểm danh', textAlign: TextAlign.center),
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
              title: Text(s['fullName']),
              subtitle: Text(info),
              trailing: StatusChip(s['status']),
              onTap: () => _setStatus(s),
            );
          },
        );

  Widget _mapTab() {
    final lat = _session['latitude'];
    final lng = _session['longitude'];
    final located = _students.where((s) => s['latitude'] != null).toList();
    if (lat == null && located.isEmpty) {
      return const EmptyView('Chưa có vị trí phòng học và chưa có sinh viên điểm danh', icon: Icons.location_off_outlined);
    }
    final room = lat == null ? null : LatLng(lat, lng);
    final center = room ?? LatLng(located.first['latitude'], located.first['longitude']);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 17),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.nguyen_chi_tu_kt',
        ),
        if (room != null)
          CircleLayer(circles: [
            CircleMarker(
              point: room,
              radius: (_session['radiusM'] as num).toDouble(),
              useRadiusInMeter: true,
              color: Colors.indigo.withValues(alpha: 0.12),
              borderColor: Colors.indigo,
              borderStrokeWidth: 2,
            ),
          ]),
        MarkerLayer(markers: [
          if (room != null)
            Marker(point: room, width: 40, height: 40, child: const Icon(Icons.meeting_room, color: Colors.indigo, size: 36)),
          for (final s in located)
            Marker(
              point: LatLng(s['latitude'], s['longitude']),
              width: 120,
              height: 48,
              child: Column(children: [
                Icon(Icons.person_pin_circle, color: attendanceLabels[s['status']]?.$2 ?? Colors.grey, size: 28),
                Text(s['fullName'].toString().split(' ').last,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
              ]),
            ),
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
      ],
    );
  }
}
