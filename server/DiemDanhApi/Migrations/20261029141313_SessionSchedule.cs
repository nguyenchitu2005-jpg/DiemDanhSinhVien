using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DiemDanhApi.Migrations
{
    /// <inheritdoc />
    public partial class SessionSchedule : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "ClosesAt",
                table: "Sessions",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "StartedAt",
                table: "Sessions",
                type: "timestamp with time zone",
                nullable: true);

            // Các buổi tạo trước đây đều đã mở điểm danh ngay khi tạo: coi là đã học để không đổi thành "chưa học"
            migrationBuilder.Sql("UPDATE \"Sessions\" SET \"StartedAt\" = \"StartAt\";");

            migrationBuilder.DropColumn(
                name: "IsOpen",
                table: "Sessions");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ClosesAt",
                table: "Sessions");

            migrationBuilder.DropColumn(
                name: "StartedAt",
                table: "Sessions");

            migrationBuilder.AddColumn<bool>(
                name: "IsOpen",
                table: "Sessions",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }
    }
}
