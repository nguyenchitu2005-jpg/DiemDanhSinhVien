using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddHttpClient();
builder.Services.AddScoped<OtpSender>();
builder.Services.AddDbContext<ApplicationDbContext>(o =>
    o.UseNpgsql(Db.ToNpgsql(builder.Configuration.GetConnectionString("DefaultConnection") ?? "")));

// Identity: mật khẩu, khoá tài khoản khi sai nhiều lần, và mã OTP 6 số (AddDefaultTokenProviders)
builder.Services.AddIdentity<User, IdentityRole>(o =>
    {
        o.User.RequireUniqueEmail = true;
        o.Lockout.MaxFailedAccessAttempts = 5;
        o.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(5);
    })
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();

var jwtSettings = builder.Configuration.GetSection("JWTKey");
var key = Encoding.UTF8.GetBytes(jwtSettings["Secret"]!);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = "Bearer";
    options.DefaultChallengeScheme = "Bearer";
})
.AddJwtBearer("Bearer", options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwtSettings["ValidIssuer"],
        ValidAudience = jwtSettings["ValidAudience"],
        IssuerSigningKey = new SymmetricSecurityKey(key)
    };
});

builder.Services.AddAuthorization();

var app = builder.Build();

// Tạo/cập nhật bảng, các role và tài khoản admin đầu tiên khi khởi động (host không chạy được lệnh dotnet ef)
using (var scope = app.Services.CreateScope())
{
    scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Database.Migrate();

    var roleManager = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
    foreach (var role in Roles.All)
        if (!await roleManager.RoleExistsAsync(role))
            await roleManager.CreateAsync(new IdentityRole(role));

    var userManager = scope.ServiceProvider.GetRequiredService<UserManager<User>>();
    var seed = app.Configuration.GetSection("SeedAdmin");
    if ((await userManager.GetUsersInRoleAsync(Roles.Admin)).Count == 0 && !string.IsNullOrEmpty(seed["Password"]))
    {
        var admin = new User { UserName = seed["UserName"], Email = seed["Email"], EmailConfirmed = true, FullName = "Quản trị viên" };
        var result = await userManager.CreateAsync(admin, seed["Password"]!);
        if (result.Succeeded) await userManager.AddToRoleAsync(admin, Roles.Admin);
        else app.Logger.LogError("Không tạo được admin: {Errors}", string.Join(" ", result.Errors.Select(e => e.Description)));
    }
}

// Bật Swagger cả trên host để demo/kiểm tra API
app.UseSwagger();
app.UseSwaggerUI();
app.MapGet("/", () => Results.Redirect("/swagger"));

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
