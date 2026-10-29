import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nguyen_chi_tu_kt/api.dart';
import 'package:nguyen_chi_tu_kt/main.dart';
import 'package:nguyen_chi_tu_kt/widgets.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'BASE_URL=https://example.com/api');
    await Auth.load();
  });

  testWidgets('Chưa đăng nhập thì mở màn đăng nhập', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Tiếp tục với Google'), findsOneWidget);
    expect(find.text('Đăng nhập bằng khuôn mặt'), findsOneWidget);
  });

  test('baseUrl luôn kết thúc bằng /', () => expect(baseUrl, 'https://example.com/api/'));

  test('deviceId tạo 1 lần và giữ nguyên', () {
    final id = Auth.deviceId;
    expect(id.length, 32);
    expect(Auth.deviceId, id);
  });

  test('fmtDate đổi giờ UTC sang giờ máy', () {
    final local = DateTime.parse('2026-10-29T07:05:00Z').toLocal();
    expect(fmtDate('2026-10-29T07:05:00Z'), '${local.day.toString().padLeft(2, '0')}/10 ${local.hour.toString().padLeft(2, '0')}:05');
    expect(fmtDate(null), '');
  });

  test('strongPassword theo luật mật khẩu của server', () {
    expect(strongPassword('Abc@12'), isNull);
    expect(strongPassword('abc@12'), 'Cần ít nhất 1 chữ in hoa');
    expect(strongPassword('ABC@12'), 'Cần ít nhất 1 chữ thường');
    expect(strongPassword('Abcd@x'), 'Cần ít nhất 1 chữ số');
    expect(strongPassword('Abc123'), 'Cần ít nhất 1 ký tự đặc biệt (vd @ # !)');
    expect(strongPassword('A@1b'), 'Tối thiểu 6 ký tự');
  });
}
