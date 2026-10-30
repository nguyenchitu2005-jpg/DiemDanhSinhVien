import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'screens/admin_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_screen.dart';
import 'screens/teacher_screen.dart';
import 'settings.dart';
import 'widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env'); // BASE_URL, GOOGLE_WEB_CLIENT_ID
  await Auth.load();
  await AppSettings.load();
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
  static ThemeData _theme(Color background, Color card) {
    final scheme = ColorScheme.fromSeed(seedColor: kGold).copyWith(surface: Colors.white);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent, foregroundColor: kInk),
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
        color: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: kCreamDeep.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.all,
    builder: (context, _) => MaterialApp(
      title: 'Điểm danh SV',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: _theme(AppSettings.background.value, AppSettings.card.value),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // cỡ chữ trong Cài đặt nhân thêm vào cỡ chữ của hệ thống
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * AppSettings.textScale.value),
        ),
        child: child!,
      ),
      home: Auth.token == null ? const LoginScreen() : homeFor(Auth.role),
    ),
  );
}
