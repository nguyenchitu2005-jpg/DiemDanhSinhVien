using Npgsql;

public static class Db
{
    /// Neon/Render cho chuỗi dạng postgresql://user:pass@host/db?sslmode=require, Npgsql cần dạng Host=...;Username=...
    public static string ToNpgsql(string connectionString)
    {
        if (!connectionString.StartsWith("postgres", StringComparison.OrdinalIgnoreCase)) return connectionString;
        var uri = new Uri(connectionString);
        var user = uri.UserInfo.Split(':', 2);
        return new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.Port > 0 ? uri.Port : 5432,
            Database = uri.AbsolutePath.Trim('/'),
            Username = Uri.UnescapeDataString(user[0]),
            Password = user.Length > 1 ? Uri.UnescapeDataString(user[1]) : null,
            SslMode = SslMode.Require,
        }.ConnectionString;
    }
}
