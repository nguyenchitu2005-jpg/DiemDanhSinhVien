using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

public class ApplicationDbContext : IdentityDbContext<User>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }
    public DbSet<Course> Courses { get; set; }
    public DbSet<Enrollment> Enrollments { get; set; }
    public DbSet<ClassSession> Sessions { get; set; }
    public DbSet<Attendance> Attendances { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder); // Identity cần tạo bảng AspNetUsers, AspNetRoles... trước
        modelBuilder.Entity<Course>().HasIndex(x => x.Code).IsUnique();
        modelBuilder.Entity<Course>().HasIndex(x => x.JoinCode).IsUnique();
        modelBuilder.Entity<Course>().HasOne(x => x.Teacher).WithMany().HasForeignKey(x => x.TeacherId).OnDelete(DeleteBehavior.SetNull);
        modelBuilder.Entity<Enrollment>().HasIndex(x => new { x.CourseId, x.StudentId }).IsUnique();
        modelBuilder.Entity<Attendance>().HasIndex(x => new { x.SessionId, x.StudentId }).IsUnique();
        // Không xoá dây chuyền từ User sang Enrollment/Attendance (2 đường User→Course→... và User→Enrollment);
        // xoá sinh viên thì UsersController tự xoá Enrollment/Attendance trước
        modelBuilder.Entity<Enrollment>().HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Restrict);
        modelBuilder.Entity<Attendance>().HasOne(x => x.Student).WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Restrict);
    }

    // Luôn lưu và trả giờ UTC (PostgreSQL timestamptz chỉ nhận UTC; JSON trả về có "Z", app đổi đúng sang giờ máy)
    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        configurationBuilder.Properties<DateTime>().HaveConversion<UtcConverter>();
    }

    private class UtcConverter() : ValueConverter<DateTime, DateTime>(
        v => v.Kind == DateTimeKind.Utc ? v : v.ToUniversalTime(),
        v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
}
