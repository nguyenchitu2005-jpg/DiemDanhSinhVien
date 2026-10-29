using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Lớp học phần: Admin CRUD + gán giảng viên; giảng viên sửa lớp của mình; sinh viên vào lớp bằng mã
[Route("api/[controller]")]
[Authorize]
public class CoursesController(ApplicationDbContext db, UserManager<User> userManager) : AppController
{
    public record CourseModel(
        [Required] string Code,
        [Required] string Name,
        string? Room,
        string? TeacherId,
        [Range(-90, 90)] double? Latitude,
        [Range(-180, 180)] double? Longitude,
        [Range(10, 5000)] int RadiusM = 100);
    public record JoinModel([Required] string JoinCode);

    /// Admin: mọi lớp; giảng viên: lớp mình dạy; sinh viên: lớp đã vào
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var uid = Uid;
        var isStudent = User.IsInRole(Roles.Student);
        var query = db.Courses.AsQueryable();
        if (User.IsInRole(Roles.Teacher)) query = query.Where(c => c.TeacherId == uid);
        else if (isStudent) query = query.Where(c => db.Enrollments.Any(e => e.CourseId == c.Id && e.StudentId == uid));

        return Ok(await query.OrderBy(c => c.Code).Select(c => new
        {
            c.Id,
            c.Code,
            c.Name,
            c.Room,
            c.TeacherId,
            TeacherName = c.Teacher != null ? c.Teacher.FullName : null,
            c.Latitude,
            c.Longitude,
            c.RadiusM,
            JoinCode = isStudent ? null : c.JoinCode,
            StudentCount = db.Enrollments.Count(e => e.CourseId == c.Id),
            SessionCount = db.Sessions.Count(s => s.CourseId == c.Id),
            OpenSessionCount = db.Sessions.Count(s => s.CourseId == c.Id && s.IsOpen),
        }).ToListAsync());
    }

    [HttpPost]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Create([FromBody] CourseModel model)
    {
        if (await TeacherError(model.TeacherId) is { } error) return BadRequest(Msg(error));
        if (await db.Courses.AnyAsync(c => c.Code == model.Code.Trim())) return BadRequest(Msg("Mã lớp đã tồn tại"));

        string joinCode;
        do joinCode = AttendanceRules.RandomCode(6);
        while (await db.Courses.AnyAsync(c => c.JoinCode == joinCode));

        var course = new Course { JoinCode = joinCode, TeacherId = model.TeacherId };
        Apply(course, model);
        db.Courses.Add(course);
        await db.SaveChangesAsync();
        return Ok(new { Status = true, Message = "Đã tạo lớp", course.Id, course.JoinCode });
    }

    /// Admin sửa mọi thứ; giảng viên sửa lớp của mình (tên, phòng, vị trí, bán kính) nhưng không đổi giảng viên
    [HttpPut("{id}")]
    [Authorize(Roles = Roles.Admin + "," + Roles.Teacher)]
    public async Task<IActionResult> Update(int id, [FromBody] CourseModel model)
    {
        var course = await ManagedCourse(db, id);
        if (course == null) return NotFound(Msg("Không tìm thấy lớp"));
        if (await db.Courses.AnyAsync(c => c.Id != id && c.Code == model.Code.Trim())) return BadRequest(Msg("Mã lớp đã tồn tại"));
        if (IsAdmin)
        {
            if (await TeacherError(model.TeacherId) is { } error) return BadRequest(Msg(error));
            course.TeacherId = model.TeacherId;
        }
        Apply(course, model);
        await db.SaveChangesAsync();
        return Done("Đã cập nhật lớp");
    }

    [HttpDelete("{id}")]
    [Authorize(Roles = Roles.Admin)]
    public async Task<IActionResult> Delete(int id)
    {
        var deleted = await db.Courses.Where(c => c.Id == id).ExecuteDeleteAsync(); // buổi học, điểm danh, danh sách SV xoá theo
        return deleted == 0 ? NotFound(Msg("Không tìm thấy lớp")) : Done("Đã xoá lớp");
    }

    [HttpPost("join")]
    [Authorize(Roles = Roles.Student)]
    public async Task<IActionResult> Join([FromBody] JoinModel model)
    {
        var code = model.JoinCode.Trim().ToUpperInvariant();
        var course = await db.Courses.FirstOrDefaultAsync(c => c.JoinCode == code);
        if (course == null) return NotFound(Msg("Mã lớp không đúng"));
        var uid = Uid;
        if (await db.Enrollments.AnyAsync(e => e.CourseId == course.Id && e.StudentId == uid))
            return BadRequest(Msg("Bạn đã ở trong lớp này"));
        db.Enrollments.Add(new Enrollment { CourseId = course.Id, StudentId = uid });
        await db.SaveChangesAsync();
        return Done($"Đã vào lớp {course.Code} - {course.Name}");
    }

    [HttpDelete("{id}/leave")]
    [Authorize(Roles = Roles.Student)]
    public Task<IActionResult> Leave(int id) => RemoveStudent(id, Uid);

    /// Danh sách sinh viên của lớp kèm số buổi có mặt (để giảng viên thấy ai có nguy cơ cấm thi)
    [HttpGet("{id}/students")]
    [Authorize(Roles = Roles.Admin + "," + Roles.Teacher)]
    public async Task<IActionResult> Students(int id)
    {
        if (await ManagedCourse(db, id) == null) return NotFound(Msg("Không tìm thấy lớp"));
        var sessionCount = await db.Sessions.CountAsync(s => s.CourseId == id);
        var students = await db.Enrollments.Where(e => e.CourseId == id).OrderBy(e => e.Student!.FullName).Select(e => new
        {
            e.StudentId,
            e.Student!.FullName,
            e.Student.StudentCode,
            e.Student.Email,
            Attended = db.Attendances.Count(a => a.StudentId == e.StudentId && a.Session!.CourseId == id && a.Status != AttendanceStatus.Excused),
        }).ToListAsync();
        return Ok(new
        {
            SessionCount = sessionCount,
            Students = students.Select(s => new
            {
                s.StudentId,
                s.FullName,
                s.StudentCode,
                s.Email,
                s.Attended,
                AtRisk = sessionCount > 0 && (double)(sessionCount - s.Attended) / sessionCount > AttendanceRules.BanAbsentRate,
            }),
        });
    }

    [HttpDelete("{id}/students/{studentId}")]
    [Authorize(Roles = Roles.Admin + "," + Roles.Teacher)]
    public async Task<IActionResult> Kick(int id, string studentId)
    {
        if (await ManagedCourse(db, id) == null) return NotFound(Msg("Không tìm thấy lớp"));
        return await RemoveStudent(id, studentId);
    }

    private async Task<IActionResult> RemoveStudent(int courseId, string studentId)
    {
        await db.Attendances.Where(a => a.StudentId == studentId && a.Session!.CourseId == courseId).ExecuteDeleteAsync();
        var deleted = await db.Enrollments.Where(e => e.CourseId == courseId && e.StudentId == studentId).ExecuteDeleteAsync();
        return deleted == 0 ? NotFound(Msg("Sinh viên không ở trong lớp")) : Done("Đã rời lớp");
    }

    private async Task<string?> TeacherError(string? teacherId)
    {
        if (string.IsNullOrEmpty(teacherId)) return null;
        var teacher = await userManager.FindByIdAsync(teacherId);
        return teacher != null && await userManager.IsInRoleAsync(teacher, Roles.Teacher) ? null : "Giảng viên không hợp lệ";
    }

    private static void Apply(Course course, CourseModel model)
    {
        course.Code = model.Code.Trim();
        course.Name = model.Name.Trim();
        course.Room = string.IsNullOrWhiteSpace(model.Room) ? null : model.Room.Trim();
        course.Latitude = model.Latitude;
        course.Longitude = model.Longitude;
        course.RadiusM = model.RadiusM;
    }
}
