using Microsoft.AspNetCore.Identity;

/// Thông báo lỗi tài khoản của Identity bằng tiếng Việt (mặc định là tiếng Anh)
public class ViIdentityErrorDescriber : IdentityErrorDescriber
{
    public override IdentityError PasswordTooShort(int length) => new() { Code = nameof(PasswordTooShort), Description = $"Mật khẩu phải có ít nhất {length} ký tự." };
    public override IdentityError PasswordRequiresNonAlphanumeric() => new() { Code = nameof(PasswordRequiresNonAlphanumeric), Description = "Mật khẩu phải có ký tự đặc biệt (vd @ # !)." };
    public override IdentityError PasswordRequiresDigit() => new() { Code = nameof(PasswordRequiresDigit), Description = "Mật khẩu phải có chữ số." };
    public override IdentityError PasswordRequiresUpper() => new() { Code = nameof(PasswordRequiresUpper), Description = "Mật khẩu phải có chữ in hoa." };
    public override IdentityError PasswordRequiresLower() => new() { Code = nameof(PasswordRequiresLower), Description = "Mật khẩu phải có chữ thường." };
    public override IdentityError PasswordMismatch() => new() { Code = nameof(PasswordMismatch), Description = "Mật khẩu hiện tại không đúng." };
    public override IdentityError DuplicateUserName(string userName) => new() { Code = nameof(DuplicateUserName), Description = $"Tên đăng nhập '{userName}' đã tồn tại." };
    public override IdentityError DuplicateEmail(string email) => new() { Code = nameof(DuplicateEmail), Description = $"Email '{email}' đã được dùng." };
    public override IdentityError InvalidUserName(string? userName) => new() { Code = nameof(InvalidUserName), Description = "Tên đăng nhập chỉ gồm chữ không dấu, số và . _ - @ +" };
    public override IdentityError InvalidEmail(string? email) => new() { Code = nameof(InvalidEmail), Description = "Email không hợp lệ." };
}
