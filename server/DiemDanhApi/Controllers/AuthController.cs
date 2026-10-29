using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Google.Apis.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;

[Route("api/[controller]")]
public class AuthController(UserManager<User> userManager, IConfiguration configuration, OtpSender otp) : AppController
{
    public record RegisterModel(
        [Required] string UserName,
        [Required, EmailAddress] string Email,
        [Required, MinLength(6)] string Password,
        [Required] string FullName,
        string? PhoneNumber,
        string? StudentCode);
    public record LoginModel([Required] string UserName, [Required] string Password, string Channel = "email");
    // Gửi lại cả mật khẩu: mã OTP chỉ có giá trị khi đi cùng mật khẩu đúng (không dò được mã nếu chỉ biết tên đăng nhập)
    public record VerifyOtpModel([Required] string UserName, [Required] string Password, [Required] string Code, string Channel = "email");
    public record GoogleModel([Required] string IdToken);
    public record FaceModel([Required] List<double> Embedding);
    public record FaceLoginModel([Required] string UserName, [Required] List<List<double>> Embeddings);
    public record ProfileModel([Required] string FullName, string? PhoneNumber, string? StudentCode);
    public record ChangePasswordModel([Required] string CurrentPassword, [Required] string NewPassword);

    private const int FaceLength = 512;

    /// Đăng ký bằng email: tạo tài khoản Sinh viên rồi gửi OTP về email để xác nhận
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterModel model)
    {
        if (await userManager.FindByNameAsync(model.UserName) != null)
            return BadRequest(Msg("Tên đăng nhập đã tồn tại"));
        if (await userManager.FindByEmailAsync(model.Email) != null)
            return BadRequest(Msg("Email đã được dùng cho tài khoản khác"));

        var user = new User
        {
            UserName = model.UserName.Trim(),
            Email = model.Email.Trim(),
            FullName = model.FullName.Trim(),
            PhoneNumber = string.IsNullOrWhiteSpace(model.PhoneNumber) ? null : model.PhoneNumber.Trim(),
            StudentCode = string.IsNullOrWhiteSpace(model.StudentCode) ? null : model.StudentCode.Trim(),
        };
        var result = await userManager.CreateAsync(user, model.Password);
        if (!result.Succeeded) return BadRequest(Msg(Errors(result)));
        await userManager.AddToRoleAsync(user, Roles.Student);

        return await SendOtp(user, "email");
    }

    /// Bước 1: đúng tên đăng nhập + mật khẩu thì gửi OTP qua email hoặc SMS
    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginModel model)
    {
        var (user, error) = await CheckPassword(model.UserName, model.Password);
        return user == null ? error! : await SendOtp(user, model.Channel);
    }

    /// Bước 2: kiểm tra OTP rồi trả JWT. Xác nhận luôn email/số điện thoại vừa nhận mã
    [HttpPost("verify-otp")]
    public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpModel model)
    {
        var (user, error) = await CheckPassword(model.UserName, model.Password);
        if (user == null) return error!;

        var sms = model.Channel == "sms";
        var provider = sms ? TokenOptions.DefaultPhoneProvider : TokenOptions.DefaultEmailProvider;
        if (!await userManager.VerifyTwoFactorTokenAsync(user, provider, model.Code.Trim()))
        {
            await userManager.AccessFailedAsync(user); // sai nhiều lần thì khoá như sai mật khẩu
            return Unauthorized(Msg("Mã OTP sai hoặc đã hết hạn"));
        }
        await userManager.ResetAccessFailedCountAsync(user);
        if (sms) user.PhoneNumberConfirmed = true;
        else user.EmailConfirmed = true;
        await userManager.UpdateAsync(user);
        return await TokenResult(user);
    }

    /// Đăng nhập/đăng ký bằng Google (OAuth 2.0): app gửi ID token, server kiểm tra chữ ký và audience với Google
    [HttpPost("google")]
    public async Task<IActionResult> Google([FromBody] GoogleModel model)
    {
        GoogleJsonWebSignature.Payload payload;
        try
        {
            payload = await GoogleJsonWebSignature.ValidateAsync(model.IdToken, new GoogleJsonWebSignature.ValidationSettings
            {
                Audience = new[] { configuration["Google:WebClientId"] },
            });
        }
        catch (InvalidJwtException e)
        {
            return Unauthorized(Msg("Token Google không hợp lệ: " + e.Message));
        }

        var user = await userManager.FindByLoginAsync("Google", payload.Subject);
        if (user == null)
        {
            if (!payload.EmailVerified) return Unauthorized(Msg("Email Google chưa được xác minh"));
            user = await userManager.FindByEmailAsync(payload.Email);
            if (user == null)
            {
                user = new User
                {
                    UserName = payload.Email,
                    Email = payload.Email,
                    EmailConfirmed = true,
                    FullName = payload.Name ?? payload.Email,
                };
                var created = await userManager.CreateAsync(user); // không có mật khẩu: chỉ đăng nhập bằng Google/khuôn mặt
                if (!created.Succeeded) return BadRequest(Msg(Errors(created)));
                await userManager.AddToRoleAsync(user, Roles.Student);
            }
            await userManager.AddLoginAsync(user, new UserLoginInfo("Google", payload.Subject, "Google"));
        }
        if (await userManager.IsLockedOutAsync(user)) return Unauthorized(Msg("Tài khoản đang bị khoá"));
        return await TokenResult(user);
    }

    [HttpPost("face")]
    [Authorize]
    public async Task<IActionResult> SaveFace([FromBody] FaceModel model)
    {
        if (model.Embedding.Count != FaceLength) return BadRequest(Msg("Vector khuôn mặt không hợp lệ"));
        var user = await userManager.GetUserAsync(User);
        if (user == null) return NotFound();
        user.FaceEmbedding = JsonSerializer.Serialize(model.Embedding);
        await userManager.UpdateAsync(user);
        return Done("Đã lưu khuôn mặt");
    }

    [HttpDelete("face")]
    [Authorize]
    public async Task<IActionResult> DeleteFace()
    {
        var user = await userManager.GetUserAsync(User);
        if (user == null) return NotFound();
        user.FaceEmbedding = null;
        await userManager.UpdateAsync(user);
        return Done("Đã xoá khuôn mặt");
    }

    /// Đăng nhập bằng khuôn mặt: app gửi vector của vài ảnh vừa chụp (đã qua kiểm tra nháy mắt), lấy ảnh khớp nhất
    [HttpPost("face-login")]
    public async Task<IActionResult> FaceLogin([FromBody] FaceLoginModel model)
    {
        var user = await FindUser(model.UserName);
        if (user?.FaceEmbedding == null) return Unauthorized(Msg("Tài khoản chưa đăng ký khuôn mặt"));
        if (await userManager.IsLockedOutAsync(user)) return Unauthorized(Msg("Tài khoản tạm khoá do sai nhiều lần, thử lại sau 5 phút"));
        if (model.Embeddings.Count == 0 || model.Embeddings.Any(e => e.Count != FaceLength))
            return BadRequest(Msg("Vector khuôn mặt không hợp lệ"));

        var reference = JsonSerializer.Deserialize<List<double>>(user.FaceEmbedding)!;
        var distance = model.Embeddings.Min(e => AttendanceRules.FaceDistance(reference, e));
        var threshold = double.Parse(configuration["Face:Threshold"] ?? "0.65", CultureInfo.InvariantCulture);
        if (distance > threshold)
        {
            await userManager.AccessFailedAsync(user);
            return Unauthorized(new { Status = false, Message = $"Khuôn mặt không khớp (khoảng cách {distance:F2}, cần ≤ {threshold:F2})" });
        }
        await userManager.ResetAccessFailedCountAsync(user);
        return await TokenResult(user);
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<IActionResult> Me()
    {
        var user = await userManager.GetUserAsync(User);
        if (user == null) return NotFound();
        return Ok(new
        {
            user.Id,
            user.UserName,
            user.Email,
            user.FullName,
            user.PhoneNumber,
            user.StudentCode,
            HasFace = user.FaceEmbedding != null,
            HasPassword = user.PasswordHash != null,
            Role = (await userManager.GetRolesAsync(user)).FirstOrDefault(),
        });
    }

    [HttpPut("me")]
    [Authorize]
    public async Task<IActionResult> UpdateMe([FromBody] ProfileModel model)
    {
        var user = await userManager.GetUserAsync(User);
        if (user == null) return NotFound();
        user.FullName = model.FullName.Trim();
        if (user.PhoneNumber != model.PhoneNumber) user.PhoneNumberConfirmed = false;
        user.PhoneNumber = string.IsNullOrWhiteSpace(model.PhoneNumber) ? null : model.PhoneNumber.Trim();
        user.StudentCode = string.IsNullOrWhiteSpace(model.StudentCode) ? null : model.StudentCode.Trim();
        var result = await userManager.UpdateAsync(user);
        return result.Succeeded ? Done("Đã cập nhật") : BadRequest(Msg(Errors(result)));
    }

    [HttpPost("change-password")]
    [Authorize]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordModel model)
    {
        var user = await userManager.GetUserAsync(User);
        if (user == null) return NotFound();
        // Tài khoản Google chưa có mật khẩu thì đặt mới luôn
        var result = user.PasswordHash == null
            ? await userManager.AddPasswordAsync(user, model.NewPassword)
            : await userManager.ChangePasswordAsync(user, model.CurrentPassword, model.NewPassword);
        return result.Succeeded ? Done("Đã đổi mật khẩu") : BadRequest(Msg(Errors(result)));
    }

    private async Task<User?> FindUser(string name) =>
        await userManager.FindByNameAsync(name.Trim())
        ?? (name.Contains('@') ? await userManager.FindByEmailAsync(name.Trim()) : null);

    private async Task<(User? User, IActionResult? Error)> CheckPassword(string name, string password)
    {
        var user = await FindUser(name);
        if (user == null) return (null, Unauthorized(Msg("Sai tên đăng nhập hoặc mật khẩu")));
        if (await userManager.IsLockedOutAsync(user))
            return (null, Unauthorized(Msg("Tài khoản tạm khoá do sai nhiều lần, thử lại sau 5 phút")));
        if (!await userManager.CheckPasswordAsync(user, password))
        {
            await userManager.AccessFailedAsync(user);
            return (null, Unauthorized(Msg("Sai tên đăng nhập hoặc mật khẩu")));
        }
        return (user, null);
    }

    private async Task<IActionResult> SendOtp(User user, string channel)
    {
        var sms = channel == "sms";
        if (sms && string.IsNullOrEmpty(user.PhoneNumber))
            return BadRequest(Msg("Tài khoản chưa có số điện thoại, hãy chọn OTP qua Email"));

        var code = await userManager.GenerateTwoFactorTokenAsync(user, sms ? TokenOptions.DefaultPhoneProvider : TokenOptions.DefaultEmailProvider);
        try
        {
            if (sms) await otp.SendSmsAsync(OtpSender.ToE164(user.PhoneNumber!), code);
            else await otp.SendEmailAsync(user.Email!, code);
        }
        catch (Exception e)
        {
            return StatusCode(StatusCodes.Status502BadGateway, Msg("Không gửi được OTP: " + e.Message));
        }
        return Ok(new { Status = true, OtpRequired = true, Channel = sms ? "sms" : "email", SentTo = Mask(sms ? user.PhoneNumber! : user.Email!) });
    }

    private async Task<IActionResult> TokenResult(User user)
    {
        var roles = await userManager.GetRolesAsync(user);
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id),
            new(ClaimTypes.Name, user.UserName!),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new("fullName", user.FullName),
        };
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));
        return Ok(new { Status = true, Token = GenerateToken(claims), Role = roles.FirstOrDefault(), user.FullName, user.UserName });
    }

    private string GenerateToken(IEnumerable<Claim> claims)
    {
        var jwtSettings = configuration.GetSection("JWTKey");
        var authSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings["Secret"]!));
        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(claims),
            Expires = DateTime.UtcNow.AddHours(Convert.ToDouble(jwtSettings["TokenExpiryTimeInHour"])),
            Issuer = jwtSettings["ValidIssuer"],
            Audience = jwtSettings["ValidAudience"],
            SigningCredentials = new SigningCredentials(authSigningKey, SecurityAlgorithms.HmacSha256)
        };
        var tokenHandler = new JwtSecurityTokenHandler();
        return tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));
    }

    // ng***@gmail.com, ***678
    private static string Mask(string s)
    {
        var at = s.IndexOf('@');
        return at > 0 ? s[..Math.Min(2, at)] + "***" + s[at..] : "***" + s[^Math.Min(3, s.Length)..];
    }
}
