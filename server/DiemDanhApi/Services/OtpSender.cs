using System.Net;
using System.Net.Mail;
using System.Net.Http.Json;

/// Gửi mã OTP qua Email: Brevo API (trên Render) hoặc Gmail SMTP
public class OtpSender(IConfiguration configuration, IHttpClientFactory httpFactory, IWebHostEnvironment env, ILogger<OtpSender> logger)
{
    private const string Subject = "Mã xác thực Điểm danh SV";

    public async Task SendEmailAsync(string to, string code)
    {
        var body = $"Mã OTP của bạn là {code}. Mã có hiệu lực vài phút, không chia sẻ cho người khác.";
        // Render gói free chặn cổng SMTP nên trên host gửi qua API HTTPS của Brevo
        var brevo = configuration.GetSection("Brevo");
        if (!string.IsNullOrEmpty(brevo["ApiKey"]))
        {
            var request = new HttpRequestMessage(HttpMethod.Post, "https://api.brevo.com/v3/smtp/email")
            {
                Content = JsonContent.Create(new
                {
                    sender = new { email = brevo["SenderEmail"], name = "Điểm danh SV" },
                    to = new[] { new { email = to } },
                    subject = $"{Subject}: {code}",
                    textContent = body,
                }),
            };
            request.Headers.Add("api-key", brevo["ApiKey"]);
            var response = await httpFactory.CreateClient().SendAsync(request);
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException("Brevo: " + await response.Content.ReadAsStringAsync());
            return;
        }

        var smtp = configuration.GetSection("Smtp");
        if (string.IsNullOrEmpty(smtp["Password"]) && LogInDevelopment(to, code)) return;

        using var client = new SmtpClient(smtp["Host"], int.Parse(smtp["Port"] ?? "587"))
        {
            EnableSsl = true,
            Credentials = new NetworkCredential(smtp["User"], smtp["Password"]),
        };
        var mail = new MailMessage(new MailAddress(smtp["User"]!, "Điểm danh SV"), new MailAddress(to))
        {
            Subject = $"{Subject}: {code}",
            Body = body,
        };
        await client.SendMailAsync(mail);
    }

    // Chạy trên máy (Development) chưa cấu hình Brevo/SMTP thì in mã ra console để test bằng Swagger
    private bool LogInDevelopment(string to, string code)
    {
        if (!env.IsDevelopment()) throw new InvalidOperationException("Máy chủ chưa cấu hình dịch vụ gửi OTP");
        logger.LogWarning("OTP cho {To}: {Code}", to, code);
        return true;
    }
}
