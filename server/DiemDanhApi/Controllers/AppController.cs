using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Phần dùng chung của các controller: id người đang đăng nhập (lấy từ token) và kiểu báo lỗi {Status, Message}
[ApiController]
public abstract class AppController : ControllerBase
{
    protected string Uid => User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    protected bool IsAdmin => User.IsInRole(Roles.Admin);

    protected static object Msg(string message) => new { Status = false, Message = message };
    protected IActionResult Done(string message) => Ok(new { Status = true, Message = message });
    /// Lớp mà người đang đăng nhập được quản lý: Admin mọi lớp, giảng viên chỉ lớp của mình
    protected Task<Course?> ManagedCourse(ApplicationDbContext db, int courseId)
    {
        var uid = Uid;
        var admin = IsAdmin;
        return db.Courses.FirstOrDefaultAsync(c => c.Id == courseId && (admin || c.TeacherId == uid));
    }

    protected static string Errors(IdentityResult result) => string.Join(" ", result.Errors.Select(e => e.Description));
}
