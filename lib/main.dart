import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api.dart';
import 'screens/admin_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_screen.dart';
import 'screens/teacher_screen.dart';
import 'widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env'); // BASE_URL, GOOGLE_WEB_CLIENT_ID
  await Auth.load();
  Auth.onExpired = () => navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
  runApp(const App());
}

/// Phân quyền: mỗi vai trò vào trang riêng
Widget homeFor(String role) => switch (role) {
  'Admin' => const AdminScreen(),
  'Teacher' => const TeacherScreen(),
  _ => const StudentScreen(),
};

class App extends StatelessWidget {
  const App({super.key});

  /// Tông vàng kem + trắng: nền trắng, thẻ màu kem nhạt, nút vàng đậm (màu gốc kGold)
  static ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(seedColor: kGold).copyWith(surface: Colors.white);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, foregroundColor: kInk),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: kCream.withValues(alpha: 0.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50), // không dùng fromHeight: nút trong hộp thoại bị kéo hết chiều ngang
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50), // không dùng fromHeight: nút trong hộp thoại bị kéo hết chiều ngang
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: kCreamDeep, foregroundColor: kInk),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFFFFFBF1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: kCreamDeep.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Điểm danh SV',
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: Auth.token == null ? const LoginScreen() : homeFor(Auth.role),
  );
}
