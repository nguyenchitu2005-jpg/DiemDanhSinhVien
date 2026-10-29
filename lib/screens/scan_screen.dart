import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';
import '../location.dart';

/// Điểm danh: vân tay (chính chủ) → lấy GPS → quét QR → gửi ngay lên server.
/// Xác thực và GPS làm TRƯỚC khi mở camera vì mã QR chỉ sống 15–30 giây.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  Position? _position;
  String _status = 'Đang chuẩn bị…';
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _error = null;
      _position = null;
    });
    try {
      final auth = LocalAuthentication();
      if (await auth.isDeviceSupported()) {
        setState(() => _status = 'Xác thực vân tay…');
        final ok = await auth.authenticate(localizedReason: 'Xác nhận chính chủ trước khi điểm danh');
        if (!ok) throw ApiException('Chưa xác thực được vân tay');
      }
      setState(() => _status = 'Đang lấy vị trí GPS…');
      final position = await currentPosition();
      if (!mounted) return;
      setState(() {
        _position = position;
        _status = 'Hướng camera vào mã QR trên màn hình giảng viên';
      });
    } on LocalAuthException catch (e) {
      _fail('Vân tay: ${e.description ?? e.code.name}');
    } catch (e) {
      _fail(e is ApiException ? e.message : 'Lỗi: $e');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final content = capture.barcodes.firstOrNull?.rawValue;
    if (_sending || _position == null || content == null) return;
    if (!content.startsWith('DD|')) {
      setState(() => _status = 'Đây không phải mã QR điểm danh');
      return;
    }
    _sending = true;
    await _scanner.stop();
    setState(() => _status = 'Đang gửi điểm danh…');
    try {
      final r = await Api.post('Attendance/checkin', {
        'qrContent': content,
        'latitude': _position!.latitude,
        'longitude': _position!.longitude,
        'deviceId': Auth.deviceId,
      });
      if (!mounted) return;
      await _result(true, r['message'], '${r['courseName']} · ${r['sessionTitle']}'
          '${r['distanceM'] != null ? '\nCách phòng học ${(r['distanceM'] as num).toStringAsFixed(0)} m' : ''}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      await _result(false, 'Điểm danh không thành công', e is ApiException ? e.message : '$e');
      _sending = false;
      setState(() => _status = 'Hướng camera vào mã QR trên màn hình giảng viên');
      await _scanner.start();
    }
  }

  Future<void> _result(bool ok, String title, String detail) => showDialog(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.red, size: 56),
      title: Text(title),
      content: Text(detail, textAlign: TextAlign.center),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(ok ? 'Xong' : 'Thử lại'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = _position != null && _error == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Quét QR điểm danh')),
      body: Column(children: [
        _Steps(fingerprint: _status != 'Xác thực vân tay…' && _status != 'Đang chuẩn bị…', gps: _position != null),
        Expanded(
          child: ready
              ? Stack(alignment: Alignment.center, children: [
                  MobileScanner(controller: _scanner, onDetect: _onDetect),
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  if (_sending) const CircularProgressIndicator(),
                ])
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_error == null) const CircularProgressIndicator() else const Icon(Icons.error_outline, size: 56, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error ?? _status, textAlign: TextAlign.center),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        FilledButton.tonal(onPressed: _prepare, child: const Text('Thử lại')),
                      ],
                    ]),
                  ),
                ),
        ),
        if (ready)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$_status\nGPS ±${_position!.accuracy.toStringAsFixed(0)} m',
              textAlign: TextAlign.center,
            ),
          ),
      ]),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.fingerprint, required this.gps});
  final bool fingerprint;
  final bool gps;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String label, bool done) => Expanded(
      child: Column(children: [
        Icon(done ? Icons.check_circle : icon, color: done ? Colors.green : Theme.of(context).colorScheme.outline),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        step(Icons.fingerprint, 'Vân tay', fingerprint),
        step(Icons.location_on_outlined, 'Vị trí GPS', gps),
        step(Icons.qr_code_scanner, 'Quét QR', false),
      ]),
    );
  }
}
