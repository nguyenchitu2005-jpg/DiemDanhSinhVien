import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'location.dart';
import 'widgets.dart';

/// Bản đồ dùng chung: chuyển Đường phố / Vệ tinh (đều của Esri, kèm tên địa danh),
/// nút phóng to – thu nhỏ, xem hết các điểm, và "vị trí của tôi" (chấm xanh).
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.center,
    this.zoom = 18,
    this.fitPoints = const [],
    this.layers = const [],
    this.onTap,
  });

  final LatLng center;
  final double zoom;

  /// Có từ 2 điểm thì mở bản đồ vừa khung chứa hết các điểm này
  final List<LatLng> fitPoints;
  final List<Widget> layers;
  final void Function(LatLng point)? onTap;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  final _map = MapController();
  bool _satellite = false;
  LatLng? _me;

  CameraFit? get _fit => widget.fitPoints.length > 1
      ? CameraFit.coordinates(coordinates: widget.fitPoints, padding: const EdgeInsets.fromLTRB(60, 60, 80, 140), maxZoom: 19)
      : null;

  void _zoom(double by) => _map.move(_map.camera.center, (_map.camera.zoom + by).clamp(3, 20));

  void _recenter() {
    final fit = _fit;
    if (fit != null) {
      _map.fitCamera(fit);
    } else {
      _map.move(widget.center, widget.zoom);
    }
  }

  Future<void> _myLocation() async {
    final p = await guard(context, currentPosition, showSuccess: false);
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    _map.move(_me!, 18);
  }

  @override
  Widget build(BuildContext context) => FlutterMap(
    mapController: _map,
    options: MapOptions(
      initialCenter: widget.center,
      initialZoom: widget.zoom,
      initialCameraFit: _fit,
      maxZoom: 20,
      onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
    ),
    children: [
      if (_satellite) ...[
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          maxNativeZoom: 19,
          userAgentPackageName: 'com.example.nguyen_chi_tu_kt',
        ),
        // Tên đường, địa danh vẽ đè lên ảnh vệ tinh
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
          maxNativeZoom: 19,
          userAgentPackageName: 'com.example.nguyen_chi_tu_kt',
        ),
      ] else
        // Không dùng tile.openstreetmap.org: một số mạng (vd mạng của máy dev) chặn tên miền này ở DNS
        TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
          maxNativeZoom: 19,
          userAgentPackageName: 'com.example.nguyen_chi_tu_kt',
        ),
      ...widget.layers,
      if (_me != null)
        MarkerLayer(markers: [
          Marker(
            point: _me!,
            width: 22,
            height: 22,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
            ),
          ),
        ]),
      RichAttributionWidget(attributions: [
        TextSourceAttribution(_satellite ? 'Esri, Maxar, Earthstar Geographics' : 'Esri, HERE, Garmin, © OpenStreetMap contributors'),
      ]),
      Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _MapButton(
              icon: _satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
              tooltip: _satellite ? 'Bản đồ đường phố' : 'Ảnh vệ tinh',
              onTap: () => setState(() => _satellite = !_satellite),
            ),
            const SizedBox(height: 12),
            _MapButton(icon: Icons.add, tooltip: 'Phóng to', onTap: () => _zoom(1)),
            _MapButton(icon: Icons.remove, tooltip: 'Thu nhỏ', onTap: () => _zoom(-1)),
            const SizedBox(height: 12),
            _MapButton(icon: Icons.center_focus_strong_outlined, tooltip: 'Xem hết', onTap: _recenter),
            _MapButton(icon: Icons.my_location, tooltip: 'Vị trí của tôi', onTap: _myLocation),
          ]),
        ),
      ),
    ],
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IconButton(tooltip: tooltip, icon: Icon(icon, color: kInk), onPressed: onTap),
    ),
  );
}

/// Vòng bán kính phòng học
CircleLayer roomCircle(LatLng room, num radiusM) => CircleLayer(circles: [
  CircleMarker(
    point: room,
    radius: radiusM.toDouble(),
    useRadiusInMeter: true,
    color: kGold.withValues(alpha: 0.18),
    borderColor: kGold,
    borderStrokeWidth: 2.5,
  ),
]);

/// Ghim phòng học
Marker roomMarker(LatLng room) => Marker(
  point: room,
  width: 48,
  height: 48,
  alignment: Alignment.topCenter, // mũi ghim chạm đúng toạ độ
  child: const Icon(Icons.location_on, color: Color(0xFFC62828), size: 48, shadows: [Shadow(color: Colors.black38, blurRadius: 6)]),
);
