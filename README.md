# Điểm danh SV – App điểm danh sinh viên (Flutter + ASP.NET Core API)

App Flutter (Dart) điểm danh bằng **QR động + GPS + vân tay**, đăng nhập bằng **mật khẩu + OTP (Email/SMS)**, **Google (OAuth 2.0)**
hoặc **khuôn mặt**. Backend là API ASP.NET Core 10 (Identity + JWT + EF Core) làm giống bài 6, **deploy lên Render** (Docker) với database
**PostgreSQL trên Neon** (không dùng localhost).

```
Nguyen_Chi_Tu_kt/
├─ lib/                     App Flutter
│  ├─ main.dart             Theme, đọc .env, phân quyền → trang theo vai trò
│  ├─ api.dart              Gọi API (JWT), lưu phiên đăng nhập, mã thiết bị
│  ├─ location.dart         Lấy GPS, chặn app giả vị trí
│  ├─ widgets.dart          Widget dùng chung
│  ├─ face/                 Nhận diện khuôn mặt (chép từ project faceid: ML Kit + FaceNet-512 TFLite, kiểm tra nháy mắt)
│  └─ screens/              login, otp, register, profile, admin, teacher, course, session, student, scan
├─ assets/models/           facenet_512.tflite
├─ .env                     BASE_URL (API đã deploy), GOOGLE_WEB_CLIENT_ID
├─ render.yaml             Cấu hình deploy Render (Blueprint)
└─ server/
   ├─ Dockerfile            Build API thành image Docker cho Render
   ├─ DiemDanhApi/          API ASP.NET Core 10 + PostgreSQL (Npgsql)
   └─ DiemDanhApi.Tests/    Test xUnit (QR, khoảng cách GPS, khuôn mặt, chuỗi kết nối)
```

## 1. Đối chiếu với đề

| Yêu cầu | Cách làm |
|---|---|
| 1. Đăng ký qua email / bên thứ 3 | `Auth/register` tạo tài khoản Sinh viên, gửi **OTP về email** để xác nhận. Nút **Tiếp tục với Google**: app lấy ID token, **server kiểm tra token với Google (OAuth 2.0)** bằng `Google.Apis.Auth`, tạo/liên kết tài khoản rồi cấp JWT |
| 2. Đăng nhập user + pass + OTP | `Auth/login` kiểm tra mật khẩu → gửi OTP 6 số qua **Email (Brevo)** hoặc **SMS (Twilio)** → `Auth/verify-otp` trả JWT. Sai mật khẩu/OTP 5 lần khoá 5 phút |
| 3. Phân quyền | Role trong JWT: **Admin** → Trang quản trị; **Teacher** (giảng viên = nhân viên) → Dashboard lớp của mình; **Student** → trang Điểm danh. API chặn bằng `[Authorize(Roles=...)]` |
| 4. CRUD | Admin: tài khoản (thêm/sửa/xoá/đổi role), lớp học (thêm/sửa/xoá/gán GV). Giảng viên: buổi học (thêm/sửa/xoá/mở-đóng), điểm danh tay (sửa trạng thái/xoá), xoá SV khỏi lớp, sửa vị trí lớp. Sinh viên: vào lớp/rời lớp, hồ sơ, khuôn mặt |
| 5a. Đăng nhập khuôn mặt | Hồ sơ → Đăng ký khuôn mặt (5 ảnh, nháy mắt chống ảnh in) → vector 512 chiều lưu trên server. Đăng nhập: server so khoảng cách vector ≤ 0.65 |
| 5b. Chia sẻ vị trí | SV gửi GPS khi điểm danh, server tính khoảng cách tới phòng học (Haversine). GV xem **bản đồ** vị trí từng SV + vòng bán kính phòng học |
| 5e. QR + vân tay | GV chiếu **QR**, SV quét bằng `mobile_scanner`; trước khi quét phải qua **vân tay** (`local_auth`) |
| 6. Tính năng mới | **Chống điểm danh hộ 4 lớp + cảnh báo cấm thi** (xem mục 2) |
| 7. Giao diện | Material 3, sáng/tối, tiếng Việt |

## 2. Tính năng mới: chống điểm danh hộ + cảnh báo cấm thi

App điểm danh hiện nay thường chỉ có QR tĩnh, nên SV chụp mã gửi cho bạn ở nhà là điểm danh hộ được. App này chặn bằng 4 lớp:

1. **QR động**: mã là HMAC(secret của buổi, thời điểm / 15 giây) và tự đổi mỗi 15 giây. Ảnh chụp mã gửi đi sẽ hết hạn sau ≤ 30 giây.
2. **Hàng rào GPS**: SV phải ở trong bán kính phòng học (GV đặt bằng vị trí hiện tại của mình). App còn từ chối khi phát hiện **app giả vị trí** (`isMocked`).
3. **Khoá thiết bị**: mỗi máy chỉ điểm danh được cho **1 SV trong 1 buổi** (cầm máy bạn quét hộ sẽ bị chặn).
4. **Vân tay chính chủ** trước khi mở camera quét.

Ngoài ra: **cảnh báo nguy cơ cấm thi**. SV vắng quá 20% số buổi đã học thì app hiện cảnh báo đỏ cho SV, và GV thấy danh sách SV có nguy cơ trong lớp.

## 3. Chạy thử trên máy (để phát triển)

Yêu cầu: Flutter 3.47 / Dart 3.13, .NET SDK 10, PostgreSQL (máy này có sẵn PostgreSQL 18).

```bash
cd server/DiemDanhApi
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=localhost;Port=5432;Database=diemdanh;Username=postgres;Password=<mat-khau-postgres>"
dotnet run --launch-profile http          # http://localhost:5080/swagger
```
- Database `diemdanh` và các bảng được tạo tự động (`Database.Migrate()`), admin mặc định `admin` / `Admin@123`.
- Chạy Development mà chưa cấu hình Brevo/Gmail/Twilio thì **mã OTP được in ra console** để test.
- App trên emulator gọi API ở máy: sửa `.env` thành `BASE_URL=http://10.0.2.2:5080/api/` (chỉ bản debug mới cho dùng http).

Test: `dotnet test server/DiemDanh.slnx` và `flutter test`.

## 4. Deploy API lên Render + Neon (bắt buộc, không dùng localhost)

Cả hai đều miễn phí và không cần thẻ tín dụng.

**Bước 1 – Database Neon (PostgreSQL)**
1. Đăng nhập https://neon.tech bằng GitHub/Google → **Create project** (region gần nhất: Singapore).
2. Bấm **Connect** → chép **connection string** dạng `postgresql://neondb_owner:...@ep-....neon.tech/neondb?sslmode=require`.
   Dán nguyên chuỗi này, server tự đổi sang định dạng của Npgsql.

**Bước 2 – Email OTP qua Brevo** (Render gói free chặn cổng SMTP nên không gửi bằng Gmail SMTP được)
1. Đăng ký https://www.brevo.com (free 300 email/ngày) → **Senders, Domains & Dedicated IPs → Senders** → thêm email gửi (Gmail của bạn) và xác nhận.
2. **SMTP & API → API Keys** → tạo API key.

**Bước 3 – Đưa code lên GitHub**
```bash
cd Nguyen_Chi_Tu_kt
git init
git add .
git commit -m "App diem danh"
git branch -M main
git remote add origin https://github.com/<tai-khoan>/<ten-repo>.git   # tạo repo trống trên github.com trước
git push -u origin main
```
`.gitignore` đã bỏ qua `bin/ obj/ build/`. Không có mật khẩu nào trong code: mọi khoá bí mật đặt ở bước 4.

**Bước 4 – Render**
1. Đăng nhập https://render.com bằng GitHub → **New → Blueprint** → chọn repo vừa push. Render đọc `render.yaml` và tạo web service `diemdanh-api` (Docker, gói Free).
2. Render hỏi giá trị các biến môi trường:

| Biến | Giá trị |
|---|---|
| `ConnectionStrings__DefaultConnection` | chuỗi Neon ở bước 1 |
| `SeedAdmin__Email`, `SeedAdmin__Password` | admin đầu tiên (mật khẩu có chữ hoa, chữ thường, số, ký tự đặc biệt, vd `Admin@123`) |
| `Brevo__ApiKey`, `Brevo__SenderEmail` | bước 2 |
| `Twilio__AccountSid`, `Twilio__AuthToken`, `Twilio__From` | mục 6 |
| `Google__WebClientId` | mục 5 |

   `JWTKey__Secret` được Render tự sinh. Biến nào chưa có thì để trống, sau này sửa ở tab **Environment** rồi bấm **Manual Deploy**.
3. Đợi build xong (lần đầu khoảng 5 phút) → mở `https://diemdanh-api-xxxx.onrender.com/swagger`. Bảng và admin được tạo ở lần chạy đầu.
4. Sửa `.env` của app: `BASE_URL=https://diemdanh-api-xxxx.onrender.com/api/`.

Gói Free của Render **tự ngủ sau 15 phút không có ai gọi**. Lần gọi đầu sau đó mất khoảng 50 giây (app đã cho chờ tới 60 giây).
Trước khi thuyết trình, hãy mở link Swagger một lần để đánh thức server.

## 5. Cấu hình Google Sign-In (OAuth 2.0)

Trên Google Cloud Console → APIs & Services → Credentials:
1. **OAuth client ID loại Web application**: đây là `GOOGLE_WEB_CLIENT_ID` (`.env`) và cũng là `Google:WebClientId` (server).
2. **OAuth client ID loại Android**: package `com.example.nguyen_chi_tu_kt`, SHA-1 lấy bằng
   `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android`.
   Mỗi thành viên trong nhóm build bằng máy mình thì phải thêm SHA-1 của máy đó.

## 6. Cấu hình SMS OTP (Twilio trial)

Đăng ký https://www.twilio.com (có credit dùng thử) → lấy **Account SID**, **Auth Token**, mua số thử (**From**).
Bản trial **chỉ gửi được tới số đã xác minh** (Verified Caller IDs) và tin nhắn có thêm câu "Sent from your Twilio trial account".
Số điện thoại trong app nhập dạng `09xxxxxxxx`, server tự đổi sang `+849xxxxxxxx`.

## 7. Kịch bản demo

1. **Admin** đăng nhập (OTP email) → tạo tài khoản giảng viên → tạo lớp và gán giảng viên.
2. **Giảng viên** đăng nhập → mở lớp → nút vị trí trên AppBar (đặt vị trí phòng) → **Tạo buổi**. QR hiện ra và tự đổi mỗi 15 giây.
3. **Sinh viên** đăng ký bằng email (OTP) → nút **Vào lớp** nhập mã lớp → **Quét QR điểm danh**: vân tay → GPS → quét.
4. Giảng viên xem tab **Danh sách** (cập nhật mỗi 5 giây) và **Bản đồ**. Sửa tay trạng thái Có phép / Vắng.
5. Thử gian lận: chụp QR gửi máy khác sau 30 giây; đứng xa phòng học; dùng 1 máy điểm danh cho 2 SV. Cả 3 trường hợp đều bị từ chối.
6. Đóng buổi → SV chưa điểm danh tính vắng → SV thấy **cảnh báo cấm thi**.
7. Hồ sơ → Đăng ký khuôn mặt → đăng xuất → **Đăng nhập bằng khuôn mặt**.

## 8. Ghi chú

- Build Android trên Windows: project ở ổ D: còn pub cache ở ổ C: nên đã tắt `kotlin.incremental` (như project faceid).
- Mã thiết bị là chuỗi ngẫu nhiên lưu trong app. Gỡ và cài lại app thì mã đổi.
- Không gửi được email OTP: xem tab **Logs** trên Render. Lỗi `Brevo: ...` thường do email gửi chưa được xác nhận trong Brevo.
