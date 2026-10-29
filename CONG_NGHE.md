# Công nghệ và thư viện sử dụng – Điểm danh SV

App điểm danh sinh viên gồm **app di động Flutter (Android)** và **API ASP.NET Core** chạy trên Render, database PostgreSQL trên Neon.
Phiên bản trong file này lấy từ `pubspec.lock`, các file `.csproj`, Gradle và lệnh `flutter --version` / `dotnet --version` của project.
Cách cài đặt, chạy và deploy: xem [README.md](README.md).

---

## 1. Tổng quan

| Nhóm | Công nghệ |
|---|---|
| App di động | Flutter 3.47.3, Dart 3.13.3, Material 3 (tông vàng kem + trắng) |
| Nền tảng | Android 7.0 trở lên (minSdk 24), build với SDK 36 |
| Backend | ASP.NET Core 10 (C#), Web API + Swagger |
| Tài khoản, phân quyền | ASP.NET Core Identity + JWT Bearer, 3 vai trò Admin / Teacher / Student |
| Database | PostgreSQL (Neon) qua Entity Framework Core 10 + Npgsql |
| Hosting | Render (Docker, gói Free) – không dùng localhost |
| Đăng nhập bên thứ 3 | Google Sign-In, backend xác thực ID token (OAuth 2.0 / OpenID Connect) |
| OTP | Mã 6 số gửi về email qua Brevo (API HTTPS) |
| Nhận diện khuôn mặt | Camera + Google ML Kit Face Detection + TensorFlow Lite (FaceNet-512) |
| Vị trí, bản đồ | Geolocator (GPS) + flutter_map với bản đồ Esri (đường phố / vệ tinh) |
| QR, vân tay | mobile_scanner (quét), qr_flutter (hiển thị), local_auth (vân tay) |
| Kiểm thử | flutter_test, xUnit |

```
┌──────────────────────── App Flutter (Android) ─────────────────────────┐
│ Đăng nhập / OTP / Google / Khuôn mặt │ Admin │ Giảng viên │ Sinh viên   │
│ api.dart (HTTP + JWT) · location.dart (GPS) · map.dart · face/ (TFLite) │
└───────────┬──────────────────┬───────────────────┬──────────────────────┘
            │ HTTPS + JWT      │ Google Sign-In     │ Tile bản đồ Esri
            ▼                  ▼                    ▼
┌──────────── API ASP.NET Core 10 (Docker trên Render) ────────────┐
│ Auth · Users · Courses · Sessions · Attendance (Controllers)     │
│ Identity + JWT · OtpSender · AttendanceRules (QR HMAC, Haversine)│
└───────┬───────────────────┬──────────────────────┬──────────────┘
        ▼                   ▼                      ▼
  PostgreSQL (Neon)    Brevo (email OTP)    Google (xác thực ID token)
```

---

## 2. Môi trường phát triển

| Thành phần | Phiên bản / ghi chú |
|---|---|
| Flutter SDK | 3.47.3 (stable), Dart 3.13.3, DevTools 2.60.0 |
| .NET SDK | 10.0 (`net10.0`) |
| Android Gradle Plugin | 9.1.0 |
| Kotlin Gradle Plugin | 2.4.0 (cho các plugin; mã app tự viết bằng Java) |
| Gradle | 9.3.1 |
| Java | 17 (`sourceCompatibility`, `jvmTarget`) |
| Android SDK | compileSdk 36, targetSdk 36, minSdk 24 |
| Trình soạn thảo | Android Studio, Visual Studio Code |
| Hệ điều hành | Windows 11 |

---

## 3. Thư viện Flutter (pub.dev)

### 3.1. Dùng trong ứng dụng

| Thư viện | Phiên bản | Dùng để |
|---|---|---|
| `http` | 1.6.0 | Gọi API (GET/POST/PUT/DELETE, gửi JWT) – `lib/api.dart` |
| `flutter_dotenv` | 6.0.1 | Đọc `.env`: `BASE_URL`, `GOOGLE_WEB_CLIENT_ID` |
| `shared_preferences` | 2.5.6 | Lưu phiên đăng nhập (token, vai trò, tên) và mã thiết bị |
| `jwt_decoder` | 2.0.1 | Kiểm tra token hết hạn khi mở app |
| `google_sign_in` | 7.2.0 | Đăng nhập Google, lấy ID token gửi cho backend |
| `mobile_scanner` | 7.4.2 | Sinh viên quét mã QR điểm danh bằng camera |
| `qr_flutter` | 4.1.0 | Giảng viên hiển thị mã QR động |
| `geolocator` | 14.1.2 | Lấy GPS, phát hiện app giả vị trí (`isMocked`) |
| `flutter_map` | 8.3.2 | Bản đồ: vị trí phòng học, vị trí sinh viên, chọn vị trí |
| `latlong2` | 0.10.1 | Kiểu toạ độ `LatLng` cho flutter_map |
| `local_auth` | 3.0.2 | Xác thực vân tay trước khi quét QR |
| `camera` | 0.12.2 | Camera trước để quét khuôn mặt |
| `google_mlkit_face_detection` | 0.15.1 | Tìm khuôn mặt, vị trí 2 mắt, phát hiện nháy mắt (chống ảnh in) |
| `tflite_flutter` | 0.12.1 | Chạy model FaceNet-512 tạo vector khuôn mặt 512 chiều |
| `image` | 4.12.0 | Xoay, cắt, căn thẳng ảnh khuôn mặt trước khi đưa vào model |
| `cupertino_icons` | 1.0.9 | Bộ icon mặc định của Flutter |

### 3.2. Dùng khi phát triển

| Thư viện | Phiên bản | Dùng để |
|---|---|---|
| `flutter_test` | SDK | Test widget và hàm tiện ích (`test/widget_test.dart`) |
| `flutter_lints` | 6.0.0 | Bộ quy tắc phân tích code (`flutter analyze`) |

### 3.3. Model và tài nguyên

| Tài nguyên | Ghi chú |
|---|---|
| `assets/models/facenet_512.tflite` | FaceNet-512 (≈24 MB), đầu vào 160×160×3, đầu ra vector 512 chiều. Phần nhận diện khuôn mặt (`lib/face/`) chép từ project `faceid` |
| `.env` | Cấu hình app, đóng gói như asset |

---

## 4. Cấu hình Android

| Mục | Giá trị / lý do |
|---|---|
| Quyền | `INTERNET`, `CAMERA`, `USE_BIOMETRIC`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` |
| `MainActivity` | `FlutterFragmentActivity` – `local_auth` cần FragmentActivity để hiện hộp thoại vân tay |
| Theme khởi động | `Theme.AppCompat.DayNight.NoActionBar` + thư viện `androidx.appcompat:appcompat:1.7.0` (yêu cầu của `local_auth`) |
| `kotlin.incremental=false` | Project ở ổ D: còn pub cache ở ổ C: → Kotlin incremental compile lỗi trên Windows |
| JVM target của `tflite_flutter` | Ép Kotlin về JVM 11 cho khớp Java (`android/build.gradle.kts`) |
| `usesCleartextTraffic` | Chỉ bản debug, để gọi API chạy trên máy (`http://10.0.2.2:5080`). Bản release chỉ dùng HTTPS |

---

## 5. Backend – API ASP.NET Core 10

### 5.1. Thư viện NuGet

| Thư viện | Phiên bản | Dùng để |
|---|---|---|
| `Microsoft.AspNetCore.Identity.EntityFrameworkCore` | 10.0.13 | Tài khoản, mật khẩu băm, vai trò, khoá tài khoản khi sai nhiều lần, mã OTP 6 số |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | 10.0.13 | Xác thực request bằng JWT |
| `Npgsql.EntityFrameworkCore.PostgreSQL` | 10.0.3 | EF Core với PostgreSQL (Neon) |
| `Microsoft.EntityFrameworkCore.Tools` | 10.0.13 | Tạo migration (`dotnet ef migrations add`) |
| `Google.Apis.Auth` | 1.73.0 | Kiểm tra chữ ký, issuer, audience, hạn dùng của Google ID token |
| `System.Security.Cryptography.Pkcs` | 10.0.13 | Ghim bản mới, thay bản 9.0.11 có lỗ hổng mà `Google.Apis.Auth` kéo vào |
| `Swashbuckle.AspNetCore` | 10.3.1 | Trang Swagger để xem và thử API |
| `xunit` / `xunit.runner.visualstudio` / `Microsoft.NET.Test.Sdk` | 2.9.3 / 3.1.4 / 17.14.1 | Test (`server/DiemDanhApi.Tests`) |

### 5.2. Cấu trúc và API chính

| Controller | Đường dẫn | Chức năng |
|---|---|---|
| `AuthController` | `api/Auth/...` | `register`, `login` (gửi OTP), `verify-otp`, `google`, `face`, `face-login`, `me`, `change-password` |
| `UsersController` (Admin) | `api/Users` | CRUD tài khoản, đổi vai trò |
| `CoursesController` | `api/Courses` | CRUD lớp (Admin), sửa vị trí lớp (GV), `join` / `leave` (SV), danh sách SV + nguy cơ cấm thi |
| `SessionsController` (GV/Admin) | `api/courses/{id}/sessions`, `api/sessions/{id}` | CRUD buổi học, mở/đóng, `qr` (mã QR hiện tại), danh sách điểm danh, điểm danh tay |
| `AttendanceController` (SV) | `api/Attendance` | `checkin` (quét QR), `history` (lịch sử + tỉ lệ vắng) |

Bảng dữ liệu: bảng Identity (`AspNetUsers`, `AspNetRoles`…), `Courses`, `Enrollments`, `Sessions`, `Attendances`.
Bảng được tạo/cập nhật tự động khi API khởi động (`Database.Migrate()`), kèm tạo vai trò và tài khoản admin đầu tiên.

### 5.3. Thuật toán và cơ chế bảo mật

| Cơ chế | Cách làm |
|---|---|
| Mật khẩu | Identity băm mật khẩu; luật: ≥ 6 ký tự, có chữ hoa, chữ thường, số, ký tự đặc biệt |
| Khoá tài khoản | Sai mật khẩu, OTP hoặc khuôn mặt 5 lần → khoá 5 phút |
| OTP | Mã 6 số theo thời gian (TOTP) của Identity, gửi về email; bước xác nhận phải gửi kèm mật khẩu nên không dò được mã chỉ với tên đăng nhập |
| JWT | HMAC-SHA256, hạn 24 giờ, chứa id, tên, vai trò |
| Google OAuth 2.0 | Backend kiểm tra ID token với Google (chữ ký, issuer, audience = Web Client ID) rồi mới cấp JWT riêng |
| QR động | Mã = HMAC-SHA256(secret của buổi, thời điểm / 15 giây); nhận mã của khung hiện tại và khung trước (sống 15–30 giây) |
| Hàng rào GPS | Công thức Haversine tính khoảng cách SV – phòng học, so với bán kính GV đặt |
| Khoá thiết bị | Mỗi mã thiết bị chỉ điểm danh cho 1 sinh viên trong 1 buổi |
| Khuôn mặt | So khoảng cách Euclid giữa vector đã đăng ký và vector vừa chụp, ngưỡng 0,65 |
| Cảnh báo cấm thi | Vắng (kể cả có phép) > 20% số buổi đã kết thúc |
| Thông báo lỗi | `ViIdentityErrorDescriber` dịch lỗi Identity sang tiếng Việt |

---

## 6. Dịch vụ bên ngoài

| Dịch vụ | Dùng để | Gói |
|---|---|---|
| **Render** | Chạy API (Docker), tự deploy khi push GitHub (`render.yaml`) | Free – ngủ sau 15 phút không dùng |
| **Neon** | PostgreSQL online | Free |
| **Brevo** | Gửi email OTP qua API HTTPS (Render free chặn cổng SMTP) | Free 300 email/ngày |
| **Google Cloud** | OAuth Client ID (loại Web cho backend, loại Android cho app) | Free |
| **Esri ArcGIS Online** | Ảnh bản đồ đường phố (World Street Map) và vệ tinh (World Imagery) | Miễn phí cho demo, có ghi nguồn trên bản đồ |
| **GitHub** | Lưu code, Render lấy code từ đây | Free |

Không dùng `tile.openstreetmap.org` vì một số mạng chặn tên miền này ở DNS (đã gặp trên máy phát triển).

---

## 7. Kiểm thử

| Bộ test | Nội dung |
|---|---|
| `test/widget_test.dart` (5 test) | Màn đăng nhập hiện đúng, `baseUrl`, mã thiết bị, định dạng giờ, luật mật khẩu |
| `server/DiemDanhApi.Tests` (7 test) | Mã QR đúng/hết hạn/sai, đọc nội dung QR, Haversine, khoảng cách vector khuôn mặt, đổi chuỗi kết nối Neon |

Chạy: `flutter test` và `dotnet test server/DiemDanh.slnx`.
