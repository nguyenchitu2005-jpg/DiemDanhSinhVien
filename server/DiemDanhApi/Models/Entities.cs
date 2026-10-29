using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Identity;

public static class Roles
{
    public const string Admin = "Admin";
    public const string Teacher = "Teacher"; // giảng viên (nhân viên)
    public const string Student = "Student";
    public static readonly string[] All = { Admin, Teacher, Student };
}

public class User : IdentityUser
{
    [MaxLength(100)]
    public string FullName { get; set; } = "";
    [MaxLength(20)]
    public string? StudentCode { get; set; }
    // Vector khuôn mặt (FaceNet-512, đã chuẩn hoá L2) dạng JSON, không lưu ảnh
    public string? FaceEmbedding { get; set; }
}

/// Lớp học phần
public class Course
{
    public int Id { get; set; }
    [MaxLength(20)]
    public string Code { get; set; } = "";
    [MaxLength(200)]
    public string Name { get; set; } = "";
    [MaxLength(50)]
    public string? Room { get; set; }
    public string? TeacherId { get; set; }
    public User? Teacher { get; set; }
    // Vị trí phòng học: sinh viên phải ở trong bán kính RadiusM mới điểm danh được
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public int RadiusM { get; set; } = 100;
    [MaxLength(10)]
    public string JoinCode { get; set; } = "";
}

public class Enrollment
{
    public int Id { get; set; }
    public int CourseId { get; set; }
    public Course? Course { get; set; }
    public string StudentId { get; set; } = "";
    public User? Student { get; set; }
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
}

/// Buổi học
public class ClassSession
{
    public int Id { get; set; }
    public int CourseId { get; set; }
    public Course? Course { get; set; }
    [MaxLength(200)]
    public string Title { get; set; } = "";
    public DateTime StartAt { get; set; } = DateTime.UtcNow;
    public int LateAfterMin { get; set; } = 15; // điểm danh sau StartAt + LateAfterMin phút là "Đi muộn"
    public bool IsOpen { get; set; } = true;
    [MaxLength(64)]
    public string QrSecret { get; set; } = "";
}

public static class AttendanceStatus
{
    public const string Present = "Present";
    public const string Late = "Late";
    public const string Excused = "Excused"; // vắng có phép
    public static readonly string[] All = { Present, Late, Excused };
}

public class Attendance
{
    public int Id { get; set; }
    public int SessionId { get; set; }
    public ClassSession? Session { get; set; }
    public string StudentId { get; set; } = "";
    public User? Student { get; set; }
    public DateTime CheckedAt { get; set; } = DateTime.UtcNow;
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public double? DistanceM { get; set; }
    [MaxLength(64)]
    public string? DeviceId { get; set; }
    [MaxLength(20)]
    public string Status { get; set; } = AttendanceStatus.Present;
    [MaxLength(10)]
    public string Method { get; set; } = "QR"; // QR | Manual
}
