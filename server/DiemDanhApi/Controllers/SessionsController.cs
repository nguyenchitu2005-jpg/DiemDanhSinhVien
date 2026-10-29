using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Buổi học: Admin tạo lịch (CRUD buổi); giảng viên chọn buổi để mở điểm danh 1 phút (QR động),
/// xem danh sách + sĩ số và điểm danh tay cho sinh viên chưa quét được
[Route("api")]
[Authorize(Roles = Roles.Admin + "," + Roles.Teacher)]
public class SessionsController(ApplicationDbContext db) : AppController
{
    public record SessionModel([Required] string Title, [Required] DateTime StartAt, [Range(0, 180)] int LateAfterMin = 15);
    /// Lịch học: Count buổi, buổi đầu lúc FirstStartAt, cách nhau EveryDays ngày (7 = mỗi tuần)
    public record ScheduleModel([Required] DateTime FirstStartAt, [Range(1, 60)] int Count, [Range(1, 31)] int EveryDays = 7, [Range(0, 180)] int LateAfterMin = 15);
    public record StatusModel([Required] string Status);

    /// Lịch các buổi của lớp (theo thời gian), kèm trạng thái điểm danh và sĩ số
    [HttpGet("courses/{courseId}/sessions")]
    public async Task<IActionResult> GetAll(int courseId)
    {
        if (await ManagedCourse(db, courseId) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var total = await db.Enrollments.CountAsync(e => e.CourseId == courseId);
        var now = DateTime.UtcNow;
        return Ok(await db.Sessions.Where(s => s.CourseId == courseId).OrderBy(s => s.StartAt).Select(s => new
        {
            s.Id,
            s.Title,
            s.StartAt,
            s.LateAfterMin,
            s.StartedAt,
            IsOpen = s.ClosesAt > now,
            PresentCount = db.Attendances.Count(a => a.SessionId == s.Id && a.Status != AttendanceStatus.Excused),
            Total = total,
        }).ToListAsync());
    }

    [HttpPost("courses/{courseId}/schedule")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Schedule(int courseId, [FromBody] ScheduleModel model)
    {
        if (await ManagedCourse(db, courseId) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var existing = await db.Sessions.CountAsync(s => s.CourseId == courseId);
        for (var i = 0; i < model.Count; i++)
            db.Sessions.Add(NewSession(courseId, $"Buổi {existing + i + 1}", model.FirstStartAt.AddDays(i * model.EveryDays), model.LateAfterMin));
        await db.SaveChangesAsync();
        return Done($"Đã tạo lịch {model.Count} buổi học");
    }

    [HttpPost("courses/{courseId}/sessions")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create(int courseId, [FromBody] SessionModel model)
    {
        if (await ManagedCourse(db, courseId) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var session = NewSession(courseId, model.Title.Trim(), model.StartAt, model.LateAfterMin);
        db.Sessions.Add(session);
        await db.SaveChangesAsync();
        return Ok(new { Status = true, Message = "Đã thêm buổi học", session.Id });
    }

    [HttpPut("sessions/{id}")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Update(int id, [FromBody] SessionModel model)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        session.Title = model.Title.Trim();
        session.StartAt = model.StartAt;
        session.LateAfterMin = model.LateAfterMin;
        await db.SaveChangesAsync();
        return Done("Đã cập nhật buổi học");
    }

    [HttpDelete("sessions/{id}")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        db.Sessions.Remove(session);
        await db.SaveChangesAsync();
        return Done("Đã xoá buổi học");
    }

    /// Mở điểm danh CheckinWindowSeconds giây (bấm lại để mở thêm); hết giờ server tự ngừng nhận
    [HttpPost("sessions/{id}/start")]
    public async Task<IActionResult> Start(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        var now = DateTime.UtcNow;
        session.StartedAt ??= now;
        session.ClosesAt = now.AddSeconds(AttendanceRules.CheckinWindowSeconds);
        await db.SaveChangesAsync();
        return Done($"Đã mở điểm danh {AttendanceRules.CheckinWindowSeconds} giây");
    }

    [HttpPost("sessions/{id}/stop")]
    public async Task<IActionResult> Stop(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        var now = DateTime.UtcNow;
        if (session.ClosesAt > now) session.ClosesAt = now;
        await db.SaveChangesAsync();
        return Done("Đã dừng điểm danh");
    }

    /// Mã QR hiện tại; app giảng viên gọi lại sau ExpiresInSeconds để hiện mã mới
    [HttpGet("sessions/{id}/qr")]
    public async Task<IActionResult> Qr(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        if (!(session.ClosesAt > DateTime.UtcNow)) return BadRequest(Msg("Buổi học chưa mở hoặc đã hết thời gian điểm danh"));
        var now = DateTimeOffset.UtcNow;
        var token = AttendanceRules.QrToken(session.QrSecret, AttendanceRules.QrWindow(now));
        return Ok(new
        {
            Content = AttendanceRules.QrContent(id, token),
            ExpiresInSeconds = AttendanceRules.QrStepSeconds - now.ToUnixTimeSeconds() % AttendanceRules.QrStepSeconds,
        });
    }

    /// Mọi sinh viên của lớp: đã điểm danh (giờ, vị trí, khoảng cách) hoặc Absent; RemainingSeconds = số giây còn nhận điểm danh
    [HttpGet("sessions/{id}/attendances")]
    public async Task<IActionResult> Attendances(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        var records = await db.Attendances.Where(a => a.SessionId == id).ToDictionaryAsync(a => a.StudentId);
        var students = await db.Enrollments.Where(e => e.CourseId == session.CourseId).OrderBy(e => e.Student!.FullName)
            .Select(e => new { e.StudentId, e.Student!.FullName, e.Student.StudentCode }).ToListAsync();
        var course = session.Course!;
        var now = DateTime.UtcNow;
        var remaining = session.ClosesAt > now ? (int)Math.Ceiling((session.ClosesAt.Value - now).TotalSeconds) : 0;
        return Ok(new
        {
            Session = new
            {
                session.Id,
                session.Title,
                session.StartAt,
                session.LateAfterMin,
                session.StartedAt,
                IsOpen = remaining > 0,
                RemainingSeconds = remaining,
                WindowSeconds = AttendanceRules.CheckinWindowSeconds,
                CourseCode = course.Code,
                CourseName = course.Name,
                course.Latitude,
                course.Longitude,
                course.RadiusM,
            },
            Students = students.Select(s =>
            {
                var a = records.GetValueOrDefault(s.StudentId);
                return new { s.StudentId, s.FullName, s.StudentCode, Status = a?.Status ?? "Absent", a?.CheckedAt, a?.Latitude, a?.Longitude, a?.DistanceM, a?.Method };
            }),
        });
    }

    private static readonly Dictionary<string, (string Label, XLColor Color)> StatusLabels = new()
    {
        [AttendanceStatus.Present] = ("Có mặt", XLColor.Green),
        [AttendanceStatus.Late] = ("Đi muộn", XLColor.DarkOrange),
        [AttendanceStatus.Excused] = ("Có phép", XLColor.Blue),
        ["Absent"] = ("Vắng", XLColor.Red),
    };

    /// File Excel danh sách điểm danh của buổi: thông tin lớp, sĩ số, từng sinh viên (trạng thái, giờ, khoảng cách, hình thức)
    [HttpGet("sessions/{id}/export")]
    public async Task<IActionResult> Export(int id)
    {
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        var course = session.Course!;
        var teacher = await db.Users.Where(u => u.Id == course.TeacherId).Select(u => u.FullName).FirstOrDefaultAsync();
        var records = await db.Attendances.Where(a => a.SessionId == id).ToDictionaryAsync(a => a.StudentId);
        var students = await db.Enrollments.Where(e => e.CourseId == session.CourseId).OrderBy(e => e.Student!.FullName)
            .Select(e => new { e.StudentId, e.Student!.FullName, e.Student.StudentCode }).ToListAsync();
        string StatusOf(string studentId) => records.GetValueOrDefault(studentId)?.Status ?? "Absent";
        int Count(string status) => students.Count(s => StatusOf(s.StudentId) == status);
        static DateTime Vn(DateTime utc) => utc.AddHours(7); // giờ Việt Nam (UTC+7, không có giờ mùa hè)

        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("Điểm danh");
        ws.Cell(1, 1).Value = "DANH SÁCH ĐIỂM DANH";
        ws.Range(1, 1, 1, 7).Merge().Style.Font.SetBold().Font.SetFontSize(14).Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);
        ws.Cell(2, 1).Value = $"Môn: {course.Code} - {course.Name}    Phòng: {course.Room ?? "-"}";
        ws.Cell(3, 1).Value = $"Buổi: {session.Title}    Ngày học: {Vn(session.StartAt):dd/MM/yyyy HH:mm}";
        ws.Cell(4, 1).Value = $"Giảng viên: {teacher ?? "-"}";
        ws.Cell(5, 1).Value = $"Sĩ số: {students.Count}    Có mặt: {Count(AttendanceStatus.Present)}    Đi muộn: {Count(AttendanceStatus.Late)}    " +
                              $"Có phép: {Count(AttendanceStatus.Excused)}    Vắng: {Count("Absent")}";
        ws.Range(5, 1, 5, 7).Style.Font.SetBold();

        string[] headers = ["STT", "Mã SV", "Họ và tên", "Trạng thái", "Giờ điểm danh", "Khoảng cách (m)", "Hình thức"];
        for (var c = 0; c < headers.Length; c++) ws.Cell(7, c + 1).Value = headers[c];
        ws.Range(7, 1, 7, headers.Length).Style.Font.SetBold().Fill.SetBackgroundColor(XLColor.FromHtml("#FFE4A1"));

        var row = 8;
        foreach (var s in students)
        {
            var a = records.GetValueOrDefault(s.StudentId);
            var (label, color) = StatusLabels[StatusOf(s.StudentId)];
            ws.Cell(row, 1).Value = row - 7;
            ws.Cell(row, 2).Value = s.StudentCode ?? "";
            ws.Cell(row, 3).Value = s.FullName;
            ws.Cell(row, 4).Value = label;
            ws.Cell(row, 4).Style.Font.SetFontColor(color).Font.SetBold();
            ws.Cell(row, 5).Value = a == null ? "" : Vn(a.CheckedAt).ToString("dd/MM/yyyy HH:mm:ss");
            if (a?.DistanceM is double d) ws.Cell(row, 6).Value = Math.Round(d);
            ws.Cell(row, 7).Value = a == null ? "" : a.Method == "QR" ? "Quét QR" : "Điểm danh tay";
            row++;
        }
        var table = ws.Range(7, 1, Math.Max(row - 1, 7), headers.Length);
        table.Style.Border.SetOutsideBorder(XLBorderStyleValues.Thin).Border.SetInsideBorder(XLBorderStyleValues.Thin);
        // Đặt độ rộng cột cố định (AdjustToContents cần font hệ thống, container trên Render có thể không có)
        double[] widths = [6, 12, 28, 12, 20, 16, 15];
        for (var c = 0; c < widths.Length; c++) ws.Column(c + 1).Width = widths[c];

        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return File(stream.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"DiemDanh_{course.Code}_{session.Title.Replace(' ', '_')}.xlsx");
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

        session.StartedAt ??= DateTime.UtcNow; // điểm danh tay cũng tính là buổi đã học
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
        var session = await Managed(id);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        session.StartedAt ??= DateTime.UtcNow;
        await db.SaveChangesAsync();
        await db.Attendances.Where(a => a.SessionId == id && a.StudentId == studentId).ExecuteDeleteAsync();
        return Done("Đã đánh vắng");
    }

    private static ClassSession NewSession(int courseId, string title, DateTime startAt, int lateAfterMin) => new()
    {
        CourseId = courseId,
        Title = title,
        StartAt = startAt,
        LateAfterMin = lateAfterMin,
        QrSecret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)),
    };

    private Task<ClassSession?> Managed(int id)
    {
        var uid = Uid;
        var admin = IsAdmin;
        return db.Sessions.Include(s => s.Course).FirstOrDefaultAsync(s => s.Id == id && (admin || s.Course!.TeacherId == uid));
    }
}
