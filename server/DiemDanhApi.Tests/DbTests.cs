using Xunit;

public class DbTests
{
    [Fact]
    public void NeonUrlConvertedToNpgsqlFormat()
    {
        var cs = Db.ToNpgsql("postgresql://neondb_owner:p%40ss@ep-cool-1.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require");
        Assert.Contains("Host=ep-cool-1.ap-southeast-1.aws.neon.tech", cs);
        Assert.Contains("Port=5432", cs);
        Assert.Contains("Database=neondb", cs);
        Assert.Contains("Username=neondb_owner", cs);
        Assert.Contains("Password=p@ss", cs);
        Assert.Contains("SSL Mode=Require", cs);
    }

    [Fact]
    public void KeyValueConnectionStringKept()
    {
        const string cs = "Host=localhost;Database=diemdanh;Username=postgres;Password=x";
        Assert.Equal(cs, Db.ToNpgsql(cs));
    }
}
