import 'package:geolocator/geolocator.dart';

import 'api.dart';

/// Vị trí GPS hiện tại; báo lỗi tiếng Việt khi tắt GPS, không cấp quyền hoặc dùng app giả vị trí
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw ApiException('Hãy bật Vị trí (GPS) trên điện thoại');
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw ApiException('App cần quyền truy cập vị trí');
  }
  // Android 12+ cho phép chỉ cấp vị trí gần đúng (sai số vài km): mở cài đặt để bật vị trí chính xác
  if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
    await Geolocator.openAppSettings();
    throw ApiException('Hãy bật "Sử dụng vị trí chính xác" trong Quyền > Vị trí của app');
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
  );
  if (position.isMocked) throw ApiException('Phát hiện ứng dụng giả lập vị trí, hãy tắt để tiếp tục');
  return position;
}
