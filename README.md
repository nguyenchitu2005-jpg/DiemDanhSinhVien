# Điểm danh SV – App điểm danh sinh viên

App di động **Flutter (Android)** điểm danh bằng **QR động + GPS + vân tay**, đăng nhập bằng **mật khẩu + OTP qua email**,
**Google (OAuth 2.0)** hoặc **khuôn mặt**. Backend là **API ASP.NET Core 10** chạy trên **Render**, database **PostgreSQL trên Neon**
(không dùng localhost).

- API: https://diemdanh-api-kuux.onrender.com/swagger
- Code: https://github.com/nguyenchitu2005-jpg/DiemDanhSinhVien
- Công nghệ và thư viện (kèm phiên bản): [CONG_NGHE.md](CONG_NGHE.md)

---

## Mục lục
1. [Chạy app (dành cho cả nhóm)](#1-chạy-app-dành-cho-cả-nhóm)
2. [Chức năng theo vai trò](#2-chức-năng-theo-vai-trò)
3. [Đối chiếu với đề](#3-đối-chiếu-với-đề)
4. [Tính năng mới: chống điểm danh hộ + cảnh báo cấm thi](#4-tính-năng-mới-chống-điểm-danh-hộ--cảnh-báo-cấm-thi)
5. [Kịch bản demo](#5-kịch-bản-demo)
6. [Cấu trúc thư mục](#6-cấu-trúc-thư-mục)
7. [Deploy và cấu hình dịch vụ](#7-deploy-và-cấu-hình-dịch-vụ)
8. [Chạy API trên máy (để phát triển)](#8-chạy-api-trên-máy-để-phát-triển)
9. [Xử lý sự cố thường gặp](#9-xử-lý-sự-cố-thường-gặp)

---

## 1. Chạy app (dành cho cả nhóm)

Yêu cầu: **Flutter 3.47** (Dart 3.13), Android Studio, điện thoại hoặc emulator **Android 7.0 trở lên**.

```bash
git clone https://github.com/nguyenchitu2005-jpg/DiemDanhSinhVien.git
cd DiemDanhSinhVien
flutter pub get
flutter run            # chọn thiết bị Android, KHÔNG chọn Chrome (web)
```

- File `.env` đã có sẵn địa chỉ API trên Render, không cần sửa.
- Trong Android Studio, ô chọn thiết bị phải là **emulator hoặc điện thoại Android**. Chạy trên **Chrome** sẽ lỗi biên dịch vì
  thư viện nhận diện khuôn mặt (`tflite_flutter`) không hỗ trợ web.
- Muốn cài thẳng lên điện thoại: `flutter build apk --release` → file `build/app/outputs/flutter-apk/app-release.apk`.
  Bản nhẹ hơn (≈50 MB) cho hầu hết điện thoại: `flutter build apk --release --split-per-abi` → dùng file `app-arm64-v8a-release.apk`.
- Server Render gói Free **ngủ sau 15 phút** không dùng; lần đầu mở app có thể chờ ~50 giây. Trước khi demo hãy mở link Swagger ở trên một lần.

---

## 2. Chức năng theo vai trò

### Chung
- **Đăng ký** tài khoản sinh viên bằng email (xác nhận bằng OTP gửi về email).
- **Đăng nhập**: tên đăng nhập/email + mật khẩu + **OTP gửi về email**; hoặc **Google**; hoặc **khuôn mặt**.
- **Hồ sơ**: sửa họ tên, số điện thoại, mã SV; đăng ký/xoá khuôn mặt; đổi mật khẩu; đăng xuất.

### Admin – Trang quản trị
- **Tài khoản**: thêm / sửa / xoá, đổi vai trò (Quản trị, Giảng viên, Sinh viên), lọc theo vai trò.
- **Lớp học**: thêm / sửa / xoá, gán giảng viên, xem mã vào lớp; mở lớp để quản lý như giảng viên.

### Giảng viên – Dashboard lớp của tôi
- Thống kê số lớp, số buổi, số buổi đang mở điểm danh.
- **Đặt vị trí phòng học trên bản đồ** (chạm để đặt ghim, kéo thanh trượt chỉnh bán kính 20–500 m, xem đường phố hoặc vệ tinh).
- **Buổi học**: tạo / sửa / xoá, mở / đóng điểm danh.
- **Màn buổi học**:
  - **Mã QR** tự đổi mỗi 15 giây, có vòng đếm ngược và số SV đã điểm danh.
  - **Danh sách** cập nhật mỗi 5 giây; bấm vào SV để điểm danh tay (Có mặt / Đi muộn / Có phép / Vắng).
  - **Bản đồ** vị trí từng SV (màu theo trạng thái, khoảng cách tới phòng, nét nối về phòng), chú thích số SV trong / ngoài vùng.
- **Sinh viên của lớp**: tỉ lệ có mặt từng SV, đánh dấu **nguy cơ cấm thi**, xoá SV khỏi lớp, chép mã vào lớp.

### Sinh viên – Trang điểm danh
- Thống kê **Lớp / Chuyên cần / Buổi vắng**; bấm vào từng ô để xem chi tiết.
- **Vào lớp** bằng mã giảng viên đưa.
- **Quét QR điểm danh**: vân tay → lấy GPS → quét mã trên màn hình giảng viên.
- Bấm vào một lớp: tỉ lệ chuyên cần, số buổi có mặt / muộn / có phép / vắng, **từng buổi học** và giờ điểm danh; rời lớp.
- **Cảnh báo nguy cơ cấm thi** khi vắng quá 20% số buổi.

---

## 3. Đối chiếu với đề

| Yêu cầu | Cách làm |
|---|---|
| 1. Đăng ký qua email / bên thứ 3 (backend OAuth 2.0) | `Auth/register` tạo tài khoản SV và gửi **OTP về email** để xác nhận. Nút **Tiếp tục với Google**: app lấy ID token, **backend kiểm tra token với Google** (chữ ký, issuer, audience) bằng `Google.Apis.Auth` rồi tạo / liên kết tài khoản và cấp JWT |
| 2. Đăng nhập user + pass + OTP (SMS, Email) | `Auth/login` kiểm tra mật khẩu → gửi **Email OTP** 6 số (qua Brevo) → `Auth/verify-otp` trả JWT. Sai mật khẩu / OTP 5 lần khoá 5 phút. Đề cho chọn SMS hoặc Email; nhóm dùng Email vì SMS cần dịch vụ trả phí |
| 3. Phân quyền | Vai trò nằm trong JWT: **Admin** → Trang quản trị; **Giảng viên** (nhân viên) → Dashboard lớp của mình; **Sinh viên** → Trang điểm danh. API chặn bằng `[Authorize(Roles = ...)]` |
| 4. CRUD | Tài khoản, lớp học (Admin); buổi học, điểm danh tay, sinh viên trong lớp, vị trí lớp (Giảng viên); vào / rời lớp, hồ sơ, khuôn mặt (Sinh viên) |
| 5a. Đăng nhập khuôn mặt | Đăng ký 5 ảnh, kiểm tra **nháy mắt** chống ảnh in → vector FaceNet 512 chiều lưu trên server; đăng nhập so khoảng cách ≤ 0,65 |
| 5b. Chia sẻ vị trí | SV gửi GPS khi điểm danh; server tính khoảng cách tới phòng (Haversine). GV xem **bản đồ** vị trí SV, chọn vị trí phòng trên bản đồ |
| 5e. QR + vân tay | GV chiếu **QR động**, SV quét bằng camera; trước khi quét phải xác thực **vân tay** |
| 6. Tính năng mới | **Chống điểm danh hộ 4 lớp + cảnh báo cấm thi** (mục 4) |
| 7. Giao diện | Material 3 tông vàng kem + trắng, tiếng Việt, thông báo lỗi tiếng Việt |
| API không dùng localhost | API chạy trên **Render**, database **Neon**; app gọi `https://diemdanh-api-kuux.onrender.com/api/` |

---

## 4. Tính năng mới: chống điểm danh hộ + cảnh báo cấm thi

App điểm danh hiện nay thường dùng QR tĩnh: SV chụp mã gửi cho bạn ở nhà là điểm danh hộ được. App này chặn bằng 4 lớp:

1. **QR động**: mã = HMAC(secret của buổi, thời điểm / 15 giây), tự đổi mỗi 15 giây. Ảnh chụp gửi đi hết hạn sau tối đa 30 giây.
2. **Hàng rào GPS**: SV phải ở trong bán kính phòng học do GV đặt. App từ chối khi phát hiện **app giả vị trí**.
3. **Khoá thiết bị**: mỗi máy chỉ điểm danh được cho **1 SV trong 1 buổi**, cầm máy bạn quét hộ sẽ bị chặn.
4. **Vân tay chính chủ** trước khi mở camera quét.

Ngoài ra: **cảnh báo nguy cơ cấm thi**. SV vắng quá 20% số buổi đã học thì app hiện cảnh báo đỏ cho SV; GV thấy SV nào có nguy cơ trong lớp.

---

## 5. Kịch bản demo

1. **Admin** đăng nhập (OTP email) → tạo tài khoản giảng viên → tạo lớp, gán giảng viên.
2. **Giảng viên** đăng nhập → mở lớp → bấm biểu tượng vị trí trên thanh tiêu đề, chọn vị trí phòng trên bản đồ → **Tạo buổi**. QR hiện ra, tự đổi mỗi 15 giây.
3. **Sinh viên** đăng ký bằng email (OTP) → **Vào lớp** bằng mã lớp → **Quét QR điểm danh**: vân tay → GPS → quét.
4. Giảng viên xem tab **Danh sách** và **Bản đồ** (bật chế độ vệ tinh); sửa tay trạng thái Có phép / Vắng.
5. Thử gian lận: chụp QR gửi máy khác sau 30 giây; đứng xa phòng học; dùng 1 máy điểm danh cho 2 SV → cả 3 đều bị từ chối.
6. Đóng buổi → SV chưa điểm danh bị tính vắng → SV thấy **cảnh báo cấm thi**, bấm ô **Buổi vắng** để xem chi tiết.
7. Hồ sơ → **Đăng ký khuôn mặt** → đăng xuất → **Đăng nhập bằng khuôn mặt**.
8. Đăng nhập **Google** bằng Gmail đã thêm vào Test users (mục 7.3).

---

## 6. Cấu trúc thư mục

```
├─ lib/                          App Flutter
│  ├─ main.dart                  Theme vàng kem, đọc .env, phân quyền → trang theo vai trò
│  ├─ api.dart                   Gọi API kèm JWT, lưu phiên đăng nhập, mã thiết bị
│  ├─ location.dart              Lấy GPS, chặn app giả vị trí
│  ├─ map.dart                   Bản đồ dùng chung (Esri đường phố / vệ tinh, nút phóng to, vị trí của tôi)
│  ├─ widgets.dart               Widget dùng chung (đầu trang, ô thống kê, thẻ, trạng thái…)
│  ├─ face/                      Nhận diện khuôn mặt (ML Kit + FaceNet-512, kiểm tra nháy mắt)
│  └─ screens/
│     ├─ login / otp / register / profile
│     ├─ admin_screen            Trang quản trị
│     ├─ teacher_screen, course_screen, session_screen, location_picker     Giảng viên
│     └─ student_screen, student_course_screen, scan_screen                 Sinh viên
├─ assets/models/                facenet_512.tflite
├─ test/                         Test Flutter
├─ .env                          BASE_URL (API trên Render), GOOGLE_WEB_CLIENT_ID
├─ render.yaml                   Cấu hình deploy Render (Blueprint)
├─ CONG_NGHE.md                  Công nghệ, thư viện, phiên bản
└─ server/
   ├─ Dockerfile                 Build API thành image cho Render
   ├─ DiemDanh.slnx
   ├─ DiemDanhApi/               API ASP.NET Core 10 (Controllers, Models, Services, Migrations)
   └─ DiemDanhApi.Tests/         Test xUnit
```

---

## 7. Deploy và cấu hình dịch vụ

Mọi dịch vụ đều miễn phí, không cần thẻ tín dụng. Không có mật khẩu nào trong code: khoá bí mật đặt bằng **biến môi trường trên Render**.

### 7.1. Database Neon (PostgreSQL)
1. Đăng nhập https://neon.tech → **Create project** (region Singapore).
2. **Connect** → chọn **Connection string** → bấm **Show password** → **Copy** chuỗi dạng
   `postgresql://neondb_owner:...@ep-....neon.tech/neondb?sslmode=require`. Dán nguyên chuỗi, server tự đổi sang định dạng Npgsql.

### 7.2. Email OTP qua Brevo
Render gói Free chặn cổng SMTP nên không gửi bằng Gmail SMTP được; server gửi qua API HTTPS của Brevo.
1. Đăng ký https://www.brevo.com. Khi điền địa chỉ: chọn **Country = Vietnam** trước rồi mới nhập mã bưu chính 5 số (vd Hà Nội `10000`, TP.HCM `70000`).
2. **Senders, Domains & Dedicated IPs → Senders** → thêm Gmail làm người gửi và xác nhận.
3. **SMTP & API → API Keys** → tạo key **Restricted**, chỉ bật **Transactional email = All**. Key chỉ hiện 1 lần.
4. Nên tắt **Security → Authorised IPs** vì Render đổi IP liên tục.

### 7.3. Google Sign-In (OAuth 2.0)
1. Tạo project: https://console.cloud.google.com/projectcreate
2. Màn đồng ý OAuth: https://console.cloud.google.com/auth/overview → **External** → thêm Gmail của cả nhóm vào **Test users**.
3. Tạo Client ID: https://console.cloud.google.com/apis/credentials → **Create Credentials → OAuth client ID**:
   - **Web application**: không cần điền URI. Client ID này dán vào `GOOGLE_WEB_CLIENT_ID` (`.env`) và `Google__WebClientId` (Render).
     Đây là mã định danh của **backend**, không liên quan tới việc build web.
   - **Android**: package `com.example.nguyen_chi_tu_kt` + SHA-1 của máy build:
     `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android`.
     Mỗi thành viên tự build trên máy mình phải thêm một Client ID Android với SHA-1 của máy đó.

### 7.4. Render
1. Code phải nằm trên GitHub. Đăng nhập https://render.com bằng GitHub → **New → Blueprint** → chọn repo.
   Render đọc `render.yaml`, tạo web service `diemdanh-api` (Docker, gói Free) và tự deploy lại mỗi khi push code trong `server/`.
2. Điền biến môi trường (tab **Environment**; tên biến dùng **2 dấu gạch dưới**):

| Biến | Giá trị |
|---|---|
| `ConnectionStrings__DefaultConnection` | Chuỗi Neon (7.1) |
| `SeedAdmin__Email`, `SeedAdmin__Password` | Admin đầu tiên: **email thật** (để nhận OTP) và mật khẩu mạnh, vd `Admin@123`. Chỉ tạo ở lần chạy đầu |
| `Brevo__ApiKey`, `Brevo__SenderEmail` | 7.2 |
| `Google__WebClientId` | Client ID loại Web (7.3) |
| `JWTKey__Secret` | Render tự sinh |

3. Build lần đầu khoảng 5 phút; thấy `Application started` trong tab **Logs** là xong. Bảng và tài khoản admin được tạo tự động.

---

## 8. Chạy API trên máy (để phát triển)

Yêu cầu: .NET SDK 10, PostgreSQL.

```bash
cd server/DiemDanhApi
# mật khẩu PostgreSQL lưu bằng user-secrets (ngoài repo, vì repo public)
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=localhost;Port=5432;Database=diemdanh;Username=postgres;Password=<mat-khau>"
dotnet run --launch-profile http          # http://localhost:5080/swagger
```

- Database `diemdanh` được tạo tự động; admin mặc định `admin` / `Admin@123`.
- Chưa cấu hình Brevo thì **mã OTP in ra console** (chỉ khi chạy Development).
- App trên emulator gọi API ở máy: tạm sửa `.env` thành `BASE_URL=http://10.0.2.2:5080/api/` (chỉ bản debug cho dùng http), nhớ trả lại trước khi commit.
- Test: `flutter test` và `dotnet test server/DiemDanh.slnx`.

---

## 9. Xử lý sự cố thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| Lỗi `Only JS interop members may be 'external'` khi chạy | Đang chạy trên **Chrome (web)**. Chọn emulator hoặc điện thoại Android |
| App chờ lâu ở lần gọi đầu | Render Free đang ngủ, đợi ~50 giây hoặc mở trước link Swagger |
| "Không gửi được OTP: Brevo …" | Email người gửi chưa xác nhận trong Brevo, sai API key, hoặc chưa tắt Authorised IPs |
| Không thấy mail OTP | Xem thư mục **Spam** |
| "Chưa cấu hình Google Sign-In" | `GOOGLE_WEB_CLIENT_ID` trong `.env` đang trống |
| Google báo `JWT audience incorrect` | `Google__WebClientId` trên Render khác Client ID trong `.env` |
| Google không cho đăng nhập | Gmail chưa có trong **Test users**, hoặc thiếu Client ID Android với SHA-1 của máy build |
| "Tài khoản tạm khoá…" | Sai mật khẩu / OTP / khuôn mặt 5 lần, đợi 5 phút |
| "Bạn đang cách phòng học … m" | Đứng ngoài bán kính; GV có thể tăng bán kính hoặc đặt lại vị trí phòng |
| "Máy này đã điểm danh cho một sinh viên khác" | Đúng thiết kế chống điểm danh hộ (1 máy / 1 SV / 1 buổi) |
| Bản đồ không hiện nền | Mạng chặn máy chủ bản đồ; app dùng Esri (không dùng OpenStreetMap vì hay bị chặn DNS) |
| Build Android lỗi cache Kotlin trên Windows | Đã tắt `kotlin.incremental` trong `android/gradle.properties` |
| Mã thiết bị đổi | Gỡ cài đặt app sẽ tạo mã thiết bị mới |
