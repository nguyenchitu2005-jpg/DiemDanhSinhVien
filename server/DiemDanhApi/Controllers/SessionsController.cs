using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Buổi học của giảng viên: CRUD, mã QR động, danh sách điểm danh và điểm danh tay
[Route("api")]
[Authorize(Roles = Roles.Admin + "," + Roles.Teacher)]
public class SessionsController(ApplicationDbContext db) : AppController
{
    public record SessionModel([Required] string Title, DateTime? StartAt, [Range(0, 180)] int LateAfterMin = 15, bool IsOpen = true);
    public record StatusModel([Required] string Status);

    [HttpGet("courses/{courseId}/sessions")]
    public async Task<IActionResult> GetAll(int courseId)
    {
        if (await ManagedCourse(db, courseId) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var total = await db.Enrollments.CountAsync(e => e.CourseId == courseId);
        return Ok(await db.Sessions.Where(s => s.CourseId == courseId).OrderByDescending(s => s.StartAt).Select(s => new
        {
            s.Id,
            s.Title,
            s.StartAt,
            s.LateAfterMin,
            s.IsOpen,
            PresentCount = db.Attendances.Count(a => a.SessionId == s.Id && a.Status != AttendanceStatus.Excused),
            Total = total,
        }).ToListAsync());
    }

    [HttpPost("courses/{courseId}/sessions")]
    public async Task<IActionResult> Create(int courseId, [FromBody] SessionModel model)
    {
        if (await ManagedCourse(db, courseId) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var session = new ClassSession
        {
            CourseId = courseId,
            Title = model.Title.Trim(),
            StartAt = model.StartAt ?? DateTime.UtcNow,
            LateAfterMin = model.LateAfterMin,
            IsOpen = model.IsOpen,
            QrSecret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)),
        };
        db.Sessions.Add(session);
        await db.SaveChangesAsync();
        return Ok(new { Status = true, Message = "Đã tạo buổi học", session.Id });
    }

    [HttpPut("sessions/{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] SessionModel model)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        session.Title = model.Title.Trim();
        session.StartAt = model.StartAt ?? session.StartAt;
        session.LateAfterMin = model.LateAfterMin;
        session.IsOpen = model.IsOpen;
        await db.SaveChangesAsync();
        return Done(session.IsOpen ? "Đã cập nhật (đang mở điểm danh)" : "Đã cập nhật (đã đóng điểm danh)");
    }

    [HttpDelete("sessions/{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        db.Sessions.Remove(session);
        await db.SaveChangesAsync();
        return Done("Đã xoá buổi học");
    }

    /// Mã QR hiện tại; app giảng viên gọi lại sau ExpiresInSeconds để hiện mã mới
    [HttpGet("sessions/{id}/qr")]
    public async Task<IActionResult> Qr(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        if (!session.IsOpen) return BadRequest(Msg("Buổi học đã đóng điểm danh"));
        var now = DateTimeOffset.UtcNow;
        var token = AttendanceRules.QrToken(session.QrSecret, AttendanceRules.QrWindow(now));
        return Ok(new
        {
            Content = AttendanceRules.QrContent(id, token),
            ExpiresInSeconds = AttendanceRules.QrStepSeconds - now.ToUnixTimeSeconds() % AttendanceRules.QrStepSeconds,
        });
    }

    /// Mọi sinh viên của lớp: đã điểm danh (giờ, vị trí, khoảng cách) hoặc Absent
    [HttpGet("sessions/{id}/attendances")]
    public async Task<IActionResult> Attendances(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        var records = await db.Attendances.Where(a => a.SessionId == id).ToDictionaryAsync(a => a.StudentId);
        var students = await db.Enrollments.Where(e => e.CourseId == session.CourseId).OrderBy(e => e.Student!.FullName)
            .Select(e => new { e.StudentId, e.Student!.FullName, e.Student.StudentCode }).ToListAsync();
        var course = session.Course!;
        return Ok(new
        {
            Session = new { session.Id, session.Title, session.StartAt, session.LateAfterMin, session.IsOpen, CourseName = course.Name, course.Latitude, course.Longitude, course.RadiusM },
            Students = students.Select(s =>
            {
                var a = records.GetValueOrDefault(s.StudentId);
                return new { s.StudentId, s.FullName, s.StudentCode, Status = a?.Status ?? "Absent", a?.CheckedAt, a?.Latitude, a?.Longitude, a?.DistanceM, a?.Method };
            }),
        });
    }

    /// Điểm danh tay: đặt Present / Late / Excused cho 1 sinh viên
    [HttpPut("sessions/{id}/attendances/{studentId}")]
    public async Task<IActionResult> SetStatus(int id, string studentId, [FromBody] StatusModel model)
    {
        if (!AttendanceStatus.All.Contains(model.Status)) return BadRequest(Msg("Trạng thái không hợp lệ"));
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        if (!await db.Enrollments.AnyAsync(e => e.CourseId == session.CourseId && e.StudentId == studentId))
            return BadRequest(Msg("Sinh viên không thuộc lớp"));

        var record = await db.Attendances.FirstOrDefaultAsync(a => a.SessionId == id && a.StudentId == studentId);
        if (record == null) db.Attendances.Add(new Attendance { SessionId = id, StudentId = studentId, Status = model.Status, Method = "Manual" });
        else record.Status = model.Status;
        await db.SaveChangesAsync();
        return Done("Đã cập nhật điểm danh");
    }

    /// Xoá bản ghi = đánh vắng
    [HttpDelete("sessions/{id}/attendances/{studentId}")]
    public async Task<IActionResult> DeleteRecord(int id, string studentId)
    {
        if (await Managed(id) == null) return NotFound(Msg("Không tìm thấy buổi học"));
        await db.Attendances.Where(a => a.SessionId == id && a.StudentId == studentId).ExecuteDeleteAsync();
        return Done("Đã đánh vắng");
    }

    private Task<ClassSession?> Managed(int id)
    {
        var uid = Uid;
        var admin = IsAdmin;
        return db.Sessions.Include(s => s.Course).FirstOrDefaultAsync(s => s.Id == id && (admin || s.Course!.TeacherId == uid));
    }
}
