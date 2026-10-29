using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Sinh viên điểm danh và xem lịch sử
[Route("api/[controller]")]
[Authorize(Roles = Roles.Student)]
public class AttendanceController(ApplicationDbContext db) : AppController
{
    public record CheckinModel([Required] string QrContent, double? Latitude, double? Longitude, [Required, MaxLength(64)] string DeviceId);

    /// Chống điểm danh hộ: QR đổi mỗi 15 giây + phải ở trong bán kính phòng học + mỗi máy chỉ điểm danh cho 1 SV/buổi
    [HttpPost("checkin")]
    public async Task<IActionResult> Checkin([FromBody] CheckinModel model)
    {
        if (AttendanceRules.ParseQr(model.QrContent) is not { } qr)
            return BadRequest(Msg("Đây không phải mã QR điểm danh"));
        var (sessionId, token) = qr;
        var session = await db.Sessions.Include(s => s.Course).FirstOrDefaultAsync(s => s.Id == sessionId);
        if (session == null) return NotFound(Msg("Không tìm thấy buổi học"));
        if (!session.IsOpen) return BadRequest(Msg("Buổi học đã đóng điểm danh"));
        var now = DateTimeOffset.UtcNow;
        if (!AttendanceRules.IsValidQr(session.QrSecret, token, now))
            return BadRequest(Msg("Mã QR đã hết hạn, hãy quét mã mới trên màn hình giảng viên"));

        var uid = Uid;
        if (!await db.Enrollments.AnyAsync(e => e.CourseId == session.CourseId && e.StudentId == uid))
            return BadRequest(Msg("Bạn không thuộc lớp này"));
        if (await db.Attendances.AnyAsync(a => a.SessionId == sessionId && a.StudentId == uid))
            return BadRequest(Msg("Bạn đã điểm danh buổi này rồi"));

        var course = session.Course!;
        double? distance = null;
        if (course.Latitude is double lat && course.Longitude is double lng)
        {
            if (model.Latitude is not double myLat || model.Longitude is not double myLng)
                return BadRequest(Msg("Cần bật vị trí (GPS) để điểm danh"));
            distance = AttendanceRules.DistanceM(lat, lng, myLat, myLng);
            if (distance > course.RadiusM)
                return BadRequest(Msg($"Bạn đang cách phòng học {distance:F0} m, chỉ được điểm danh trong {course.RadiusM} m"));
        }
        if (await db.Attendances.AnyAsync(a => a.SessionId == sessionId && a.DeviceId == model.DeviceId))
            return BadRequest(Msg("Máy này đã điểm danh cho một sinh viên khác trong buổi này"));

        var status = now.UtcDateTime > session.StartAt.AddMinutes(session.LateAfterMin) ? AttendanceStatus.Late : AttendanceStatus.Present;
        db.Attendances.Add(new Attendance
        {
            SessionId = sessionId,
            StudentId = uid,
            Latitude = model.Latitude,
            Longitude = model.Longitude,
            DistanceM = distance,
            DeviceId = model.DeviceId,
            Status = status,
        });
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException) // 2 lần quét cùng lúc: index unique (SessionId, StudentId) chặn bản ghi thứ 2
        {
            return BadRequest(Msg("Bạn đã điểm danh buổi này rồi"));
        }
        return Ok(new
        {
            Status = true,
            Message = status == AttendanceStatus.Late ? "Điểm danh thành công (đi muộn)" : "Điểm danh thành công",
            AttendanceStatus = status,
            DistanceM = distance,
            CourseName = course.Name,
            SessionTitle = session.Title,
        });
    }

    /// Lịch sử từng lớp + tỉ lệ vắng; vắng quá 20% số buổi đã học thì cảnh báo nguy cơ cấm thi
    [HttpGet("history")]
    public async Task<IActionResult> History()
    {
        var uid = Uid;
        var courses = await db.Enrollments.Where(e => e.StudentId == uid).Select(e => e.Course!).OrderBy(c => c.Code).ToListAsync();
        var courseIds = courses.Select(c => c.Id).ToList();
        var sessions = await db.Sessions.Where(s => courseIds.Contains(s.CourseId)).OrderByDescending(s => s.StartAt)
            .Select(s => new { s.Id, s.CourseId, s.Title, s.StartAt, s.IsOpen }).ToListAsync();
        var mine = await db.Attendances.Where(a => a.StudentId == uid)
            .Select(a => new { a.SessionId, a.Status, a.CheckedAt }).ToDictionaryAsync(a => a.SessionId);

        return Ok(courses.Select(c =>
        {
            var list = sessions.Where(s => s.CourseId == c.Id).Select(s =>
            {
                var a = mine.GetValueOrDefault(s.Id);
                // Buổi còn mở mà chưa điểm danh thì chưa tính vắng
                return new { s.Id, s.Title, s.StartAt, s.IsOpen, Status = a?.Status ?? (s.IsOpen ? "Open" : "Absent"), a?.CheckedAt };
            }).ToList();
            var counted = list.Count(x => x.Status != "Open");
            var absent = list.Count(x => x.Status is "Absent" or AttendanceStatus.Excused);
            var rate = counted == 0 ? 0 : (double)absent / counted;
            return new
            {
                c.Id,
                c.Code,
                c.Name,
                c.Room,
                TotalSessions = counted,
                Absent = absent,
                AbsentRate = rate,
                Warning = rate > AttendanceRules.BanAbsentRate,
                Sessions = list,
            };
        }));
    }
}
