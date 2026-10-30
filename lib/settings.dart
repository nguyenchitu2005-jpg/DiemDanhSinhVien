import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cài đặt giao diện lưu trên máy: cỡ chữ, màu nền, màu ô. App lắng nghe để vẽ lại ngay khi đổi
class AppSettings {
  static late SharedPreferences _prefs;
  static final textScale = ValueNotifier<double>(1);
  static final background = ValueNotifier<Color>(Colors.white);
  static final card = ValueNotifier<Color>(const Color(0xFFFFFBF1));

  /// Màu cho chọn: chỉ tông sáng để chữ nâu đậm vẫn đọc rõ
  static const backgrounds = {
    'Trắng': Colors.white,
    'Kem': Color(0xFFFFFBF1),
    'Xanh lá': Color(0xFFF0F8EE),
    'Xanh dương': Color(0xFFEEF4FB),
    'Hồng': Color(0xFFFCF0F3),
    'Xám': Color(0xFFF3F3F3),
  };

  /// Màu ô đậm hơn màu nền một chút để ô vẫn tách khỏi nền
  static const cards = {
    'Kem': Color(0xFFFFFBF1),
    'Trắng': Colors.white,
    'Vàng': Color(0xFFFFF1C9),
    'Xanh lá': Color(0xFFE3F2DE),
    'Xanh dương': Color(0xFFE0ECF9),
    'Hồng': Color(0xFFFAE3EA),
    'Xám': Color(0xFFEAEAEA),
  };

  static Listenable get all => Listenable.merge([textScale, background, card]);

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    textScale.value = _prefs.getDouble('textScale') ?? 1;
    background.value = Color(_prefs.getInt('background') ?? background.value.toARGB32());
    card.value = Color(_prefs.getInt('card') ?? card.value.toARGB32());
  }

  static Future<void> setTextScale(double value) async {
    textScale.value = value;
    await _prefs.setDouble('textScale', value);
  }

  static Future<void> setBackground(Color value) async {
    background.value = value;
    await _prefs.setInt('background', value.toARGB32());
  }

  static Future<void> setCard(Color value) async {
    card.value = value;
    await _prefs.setInt('card', value.toARGB32());
  }
}
