using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Testcontainers.PostgreSql;
using Xunit;

namespace Api.IntegrationTests;

// Runs the whole API in-process against a throwaway Postgres. Nothing here reaches a real server:
// the database is a container started for the test run, and tokens are signed with a test-only key.
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    // Pinned to production's major version (our DigitalOcean Postgres is 17).
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder().WithImage("postgres:17").Build();

    // Valid only inside this test host. Never a key from a real identity provider.
    private static readonly SymmetricSecurityKey TestSigningKey =
        new(Encoding.UTF8.GetBytes("test-only-signing-key-not-a-secret-0123456789"));

    public Task InitializeAsync() => _db.StartAsync();

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _db.DisposeAsync();
        await base.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        // The key your app reads its connection string from.
        builder.UseSetting("ConnectionStrings:Default", _db.GetConnectionString());
        builder.ConfigureServices(services =>
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, o =>
            {
                // No identity provider: no authority, no metadata download, only the test key.
                o.Authority = null;
                o.ConfigurationManager = null;
                o.TokenValidationParameters = new TokenValidationParameters
                {
                    IssuerSigningKey = TestSigningKey,
                    ValidateIssuer = false,
                    ValidateAudience = false,
                };
            }));
    }

    // A token the API accepts in this test host only. Add the claims your endpoints check.
    public static string TestToken(params Claim[] claims) => new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
    {
        Subject = new ClaimsIdentity(claims.Append(new Claim("sub", "test-user"))),
        Expires = DateTime.UtcNow.AddMinutes(10),
        SigningCredentials = new SigningCredentials(TestSigningKey, SecurityAlgorithms.HmacSha256),
    });

    public HttpClient CreateAuthorizedClient()
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", TestToken());
        return client;
    }
}
