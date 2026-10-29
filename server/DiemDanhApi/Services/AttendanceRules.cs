using System.Security.Cryptography;
using System.Text;

/// Luật điểm danh dùng chung (thuần tính toán, có test trong DiemDanhApi.Tests)
public static class AttendanceRules
{
    /// Mã QR đổi sau mỗi chừng này giây: ảnh QR chụp gửi cho bạn sẽ hết hạn rất nhanh
    public const int QrStepSeconds = 15;

    public static long QrWindow(DateTimeOffset now) => now.ToUnixTimeSeconds() / QrStepSeconds;

    public static string QrToken(string secret, long window) =>
        Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(window.ToString())))[..12];

    /// Nhận cả mã của khung trước để sinh viên quét sát lúc đổi mã không bị từ chối
    public static bool IsValidQr(string secret, string token, DateTimeOffset now)
    {
        var w = QrWindow(now);
        return token == QrToken(secret, w) || token == QrToken(secret, w - 1);
    }

    /// Nội dung mã QR: DD|{sessionId}|{token}
    public static string QrContent(int sessionId, string token) => $"DD|{sessionId}|{token}";

    public static (int SessionId, string Token)? ParseQr(string content)
    {
        var parts = content.Split('|');
        return parts.Length == 3 && parts[0] == "DD" && int.TryParse(parts[1], out var id) ? (id, parts[2]) : null;
    }

    /// Khoảng cách (mét) giữa 2 toạ độ GPS theo công thức Haversine
    public static double DistanceM(double lat1, double lng1, double lat2, double lng2)
    {
        const double r = 6371000;
        double Rad(double d) => d * Math.PI / 180;
        var dLat = Rad(lat2 - lat1);
        var dLng = Rad(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * r * Math.Asin(Math.Sqrt(a));
    }

    /// Khoảng cách Euclid giữa 2 vector khuôn mặt (đã chuẩn hoá L2, 0..2): nhỏ hơn ngưỡng là cùng người
    public static double FaceDistance(IReadOnlyList<double> a, IReadOnlyList<double> b)
    {
        if (a.Count != b.Count) return double.MaxValue;
        double sum = 0;
        for (var i = 0; i < a.Count; i++) sum += (a[i] - b[i]) * (a[i] - b[i]);
        return Math.Sqrt(sum);
    }

    /// Vắng quá 20% số buổi là nguy cơ cấm thi
    public const double BanAbsentRate = 0.2;

    public static string RandomCode(int length)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // bỏ O/0, I/1 cho dễ đọc
        return RandomNumberGenerator.GetString(chars, length);
    }
}
