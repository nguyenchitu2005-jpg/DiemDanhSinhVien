import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location.dart';
import '../map.dart';
import '../widgets.dart';

/// Chọn vị trí phòng học: chạm lên bản đồ (đường phố / vệ tinh) để đặt ghim hoặc lấy GPS hiện tại,
/// kéo thanh trượt để chỉnh bán kính điểm danh. Trả về (toạ độ, bán kính mét).
class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key, this.initial, this.radiusM = 100});
  final LatLng? initial;
  final int radiusM;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  LatLng? _point;
  late int _radius = widget.radiusM.clamp(20, 500);
  double? _accuracy; // sai số GPS khi lấy vị trí hiện tại
  Key _mapKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _point = widget.initial;
    if (_point == null) _useGps();
  }

  Future<void> _useGps() async {
    final p = await guard(context, currentPosition, showSuccess: false);
    if (p == null || !mounted) return;
    setState(() {
      _point = LatLng(p.latitude, p.longitude);
      _accuracy = p.accuracy;
      _mapKey = UniqueKey(); // dựng lại bản đồ để căn giữa vị trí mới
    });
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    return Scaffold(
      appBar: AppBar(title: const Text('Vị trí phòng học')),
      body: point == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Đang lấy vị trí GPS…'),
              ]),
            )
          : Column(children: [
              Expanded(
                child: AppMap(
                  key: _mapKey,
                  center: point,
                  onTap: (p) => setState(() {
                    _point = p;
                    _accuracy = null;
                  }),
                  layers: [
                    roomCircle(point, _radius),
                    MarkerLayer(markers: [roomMarker(point)]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Chạm lên bản đồ để đặt ghim đúng vị trí phòng học', style: TextStyle(color: kInk)),
                    const SizedBox(height: 4),
                    Text(
                      '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'
                      '${_accuracy != null ? ' (GPS ±${_accuracy!.toStringAsFixed(0)} m)' : ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.radar, color: kGold),
                      const SizedBox(width: 8),
                      Text('Bán kính $_radius m', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: _radius.toDouble(),
                          min: 20,
                          max: 500,
                          divisions: 48,
                          label: '$_radius m',
                          onChanged: (v) => setState(() => _radius = v.round()),
                        ),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(onPressed: _useGps, icon: const Icon(Icons.my_location), label: const Text('Vị trí của tôi')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, (point, _radius)),
                          icon: const Icon(Icons.check),
                          label: const Text('Lưu'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
    );
  }
}
