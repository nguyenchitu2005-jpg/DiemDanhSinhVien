using Xunit;

public class AttendanceRulesTests
{
    private const string Secret = "ABC123";
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    [Fact]
    public void QrCurrentAndPreviousWindowAccepted()
    {
        var token = AttendanceRules.QrToken(Secret, AttendanceRules.QrWindow(Now));
        Assert.True(AttendanceRules.IsValidQr(Secret, token, Now));
        Assert.True(AttendanceRules.IsValidQr(Secret, token, Now.AddSeconds(AttendanceRules.QrStepSeconds)));
    }

    [Fact]
    public void QrExpiredOrWrongSecretRejected()
    {
        var token = AttendanceRules.QrToken(Secret, AttendanceRules.QrWindow(Now));
        Assert.False(AttendanceRules.IsValidQr(Secret, token, Now.AddSeconds(AttendanceRules.QrStepSeconds * 2)));
        Assert.False(AttendanceRules.IsValidQr("OTHER", token, Now));
    }

    [Fact]
    public void QrContentRoundTrip()
    {
        Assert.Equal((42, "TOKEN"), AttendanceRules.ParseQr(AttendanceRules.QrContent(42, "TOKEN")));
        Assert.Null(AttendanceRules.ParseQr("https://example.com"));
        Assert.Null(AttendanceRules.ParseQr("DD|x|TOKEN"));
    }

    [Fact]
    public void HaversineDistance()
    {
        // 0.001 độ vĩ ≈ 111 m
        Assert.InRange(AttendanceRules.DistanceM(10.0, 106.0, 10.001, 106.0), 110, 112);
        Assert.Equal(0, AttendanceRules.DistanceM(10.0, 106.0, 10.0, 106.0), 6);
    }

    [Fact]
    public void FaceDistanceOfDifferentLengthNeverMatches()
    {
        Assert.Equal(double.MaxValue, AttendanceRules.FaceDistance(new[] { 1.0 }, new[] { 1.0, 0 }));
        Assert.Equal(Math.Sqrt(2), AttendanceRules.FaceDistance(new[] { 1.0, 0 }, new[] { 0, 1.0 }), 6);
    }
}
