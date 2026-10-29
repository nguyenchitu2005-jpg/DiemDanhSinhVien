import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Đường dẫn gốc của API lấy từ file .env (BASE_URL), luôn kết thúc bằng "/"
String get baseUrl {
  final url = dotenv.env['BASE_URL'] ?? '';
  return url.endsWith('/') ? url : '$url/';
}

/// Lỗi hiển thị được cho người dùng (câu tiếng Việt API trả về)
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Người đang đăng nhập: token JWT + vai trò, lưu trong SharedPreferences
class Auth {
  static late SharedPreferences _prefs;
  static String? token;
  static String role = '';
  static String fullName = '';
  static String userName = '';

  /// Gọi khi token hết hạn (API trả 401) để app quay về màn đăng nhập
  static void Function()? onExpired;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    token = _prefs.getString('token');
    if (token != null && JwtDecoder.isExpired(token!)) token = null;
    role = _prefs.getString('role') ?? '';
    fullName = _prefs.getString('fullName') ?? '';
    userName = _prefs.getString('userName') ?? '';
  }

  /// Lưu kết quả đăng nhập {token, role, fullName, userName}
  static Future<void> save(Map<String, dynamic> result) async {
    token = result['token'];
    role = result['role'] ?? '';
    fullName = result['fullName'] ?? '';
    userName = result['userName'] ?? '';
    await _prefs.setString('token', token!);
    await _prefs.setString('role', role);
    await _prefs.setString('fullName', fullName);
    await _prefs.setString('userName', userName); // điền sẵn khi đăng nhập bằng khuôn mặt lần sau
  }

  static Future<void> logout() async {
    token = null;
    await _prefs.remove('token');
  }

  /// Mã ngẫu nhiên của máy, tạo 1 lần: server chặn 1 máy điểm danh cho 2 sinh viên trong cùng buổi.
  /// shortcut: cài lại app thì mã đổi; muốn chặt hơn thì dùng Android ID qua device_info_plus
  static String get deviceId {
    var id = _prefs.getString('deviceId');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _prefs.setString('deviceId', id);
    }
    return id;
  }
}

/// Gọi API: Api.get('Courses'), Api.post('Auth/login', {...}). Trả về JSON đã giải mã, lỗi ném ApiException
class Api {
  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);
  static Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Tải file (vd Excel) dạng byte
  static Future<Uint8List> download(String path) async {
    final res = await _raw('GET', path);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    _check(res); // ném ApiException với thông báo của server
    throw ApiException('Lỗi máy chủ (${res.statusCode})');
  }

  static Future<dynamic> _send(String method, String path, [Object? body]) async => _check(await _raw(method, path, body));

  static Future<http.Response> _raw(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json';
    if (Auth.token != null) request.headers['Authorization'] = 'Bearer ${Auth.token}';
    if (body != null) request.body = jsonEncode(body);
    try {
      // Host miễn phí ngủ khi không ai dùng, lần gọi đầu có thể mất vài chục giây
      return await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 60)));
    } on SocketException {
      throw ApiException('Không kết nối được máy chủ, kiểm tra mạng');
    } on TimeoutException {
      throw ApiException('Máy chủ phản hồi quá lâu, thử lại sau');
    } on http.ClientException {
      throw ApiException('Không kết nối được máy chủ');
    }
  }

  static dynamic _check(http.Response res) {
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      data = null; // trang lỗi HTML của host
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && Auth.token != null) {
      Auth.logout();
      Auth.onExpired?.call();
      throw ApiException('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại');
    }
    if (res.statusCode == 403) throw ApiException('Bạn không có quyền thực hiện thao tác này');
    if (data is Map) {
      // Lỗi kiểm tra dữ liệu của ASP.NET: {errors: {Email: ["..."]}}
      final errors = data['errors'];
      if (errors is Map) throw ApiException(errors.values.expand((e) => e is List ? e : [e]).join('\n'));
      if (data['message'] != null) throw ApiException(data['message'].toString());
    }
    throw ApiException('Lỗi máy chủ (${res.statusCode})');
  }
}
