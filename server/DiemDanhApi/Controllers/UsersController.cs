using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

/// Trang quản trị: CRUD tài khoản và phân quyền
[Route("api/[controller]")]
[Authorize(Roles = Roles.Admin)]
public class UsersController(UserManager<User> userManager, ApplicationDbContext db) : AppController
{
    public record UserModel(
        [Required] string UserName,
        [Required, EmailAddress] string Email,
        [Required] string FullName,
        [Required] string Role,
        string? PhoneNumber,
        string? StudentCode,
        string? Password); // bắt buộc khi tạo; khi sửa để trống là giữ mật khẩu cũ

    [HttpGet]
    public async Task<IActionResult> GetAll(string? role)
    {
        var roleOf = (await db.UserRoles.Join(db.Roles, ur => ur.RoleId, r => r.Id, (ur, r) => new { ur.UserId, r.Name }).ToListAsync())
            .DistinctBy(x => x.UserId).ToDictionary(x => x.UserId, x => x.Name);
        var users = await db.Users.OrderBy(u => u.FullName)
            .Select(u => new { u.Id, u.UserName, u.Email, u.FullName, u.PhoneNumber, u.StudentCode, HasFace = u.FaceEmbedding != null })
            .ToListAsync();
        return Ok(users
            .Select(u => new { u.Id, u.UserName, u.Email, u.FullName, u.PhoneNumber, u.StudentCode, u.HasFace, Role = roleOf.GetValueOrDefault(u.Id) })
            .Where(u => role == null || u.Role == role));
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] UserModel model)
    {
        if (!Roles.All.Contains(model.Role)) return BadRequest(Msg("Vai trò không hợp lệ"));
        if (string.IsNullOrEmpty(model.Password)) return BadRequest(Msg("Cần nhập mật khẩu"));
        var user = new User { EmailConfirmed = true };
        Apply(user, model);
        var result = await userManager.CreateAsync(user, model.Password);
        if (!result.Succeeded) return BadRequest(Msg(Errors(result)));
        await userManager.AddToRoleAsync(user, model.Role);
        return Done("Đã tạo tài khoản");
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(string id, [FromBody] UserModel model)
    {
        if (!Roles.All.Contains(model.Role)) return BadRequest(Msg("Vai trò không hợp lệ"));
        var user = await userManager.FindByIdAsync(id);
        if (user == null) return NotFound(Msg("Không tìm thấy tài khoản"));
        if (id == Uid && model.Role != Roles.Admin) return BadRequest(Msg("Không thể tự bỏ quyền Admin của chính mình"));

        Apply(user, model);
        var result = await userManager.UpdateAsync(user);
        if (!result.Succeeded) return BadRequest(Msg(Errors(result)));

        var roles = await userManager.GetRolesAsync(user);
        if (!roles.SequenceEqual(new[] { model.Role }))
        {
            await userManager.RemoveFromRolesAsync(user, roles);
            await userManager.AddToRoleAsync(user, model.Role);
        }
        if (!string.IsNullOrEmpty(model.Password))
        {
            var reset = await userManager.ResetPasswordAsync(user, await userManager.GeneratePasswordResetTokenAsync(user), model.Password);
            if (!reset.Succeeded) return BadRequest(Msg(Errors(reset)));
        }
        return Done("Đã cập nhật tài khoản");
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(string id)
    {
        if (id == Uid) return BadRequest(Msg("Không thể xoá tài khoản đang đăng nhập"));
        var user = await userManager.FindByIdAsync(id);
        if (user == null) return NotFound(Msg("Không tìm thấy tài khoản"));
        // Lớp của giảng viên tự bỏ trống giảng viên (SetNull); dữ liệu của sinh viên phải xoá tay (xem ApplicationDbContext)
        await db.Attendances.Where(a => a.StudentId == id).ExecuteDeleteAsync();
        await db.Enrollments.Where(e => e.StudentId == id).ExecuteDeleteAsync();
        var result = await userManager.DeleteAsync(user);
        return result.Succeeded ? Done("Đã xoá tài khoản") : BadRequest(Msg(Errors(result)));
    }

    private static void Apply(User user, UserModel model)
    {
        user.UserName = model.UserName.Trim();
        user.Email = model.Email.Trim();
        user.FullName = model.FullName.Trim();
        user.PhoneNumber = string.IsNullOrWhiteSpace(model.PhoneNumber) ? null : model.PhoneNumber.Trim();
        user.StudentCode = string.IsNullOrWhiteSpace(model.StudentCode) ? null : model.StudentCode.Trim();
    }
}
