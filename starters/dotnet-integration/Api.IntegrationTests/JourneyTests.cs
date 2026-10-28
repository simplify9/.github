using System.Net;
using System.Net.Http.Json;
using Xunit;

namespace Api.IntegrationTests;

// 3-5 critical journeys. Replace /items with your API's real endpoints and payloads.
public sealed class JourneyTests(ApiFactory api) : IClassFixture<ApiFactory>
{
    [Fact]
    public async Task Health_returns_200()
    {
        var response = await api.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Write_then_read_round_trip()
    {
        var client = api.CreateAuthorizedClient();
        var created = await client.PostAsJsonAsync("/items", new { name = "First item" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        var read = await client.GetFromJsonAsync<Item>(created.Headers.Location);
        Assert.Equal("First item", read?.Name);
    }

    [Fact]
    public async Task Invalid_token_returns_401()
    {
        var client = api.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", "not-a-valid-token");
        var response = await client.GetAsync("/items/1");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Test_key_token_is_accepted()
    {
        var response = await api.CreateAuthorizedClient().PostAsJsonAsync("/items", new { name = "Second item" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // [Fact]
    // public async Task Main_endpoint_journey()
    // {
    //     var client = api.CreateAuthorizedClient();
    //     // Arrange the data the journey needs through the API, call the endpoint, assert what a user relies on.
    // }

    private sealed record Item(int Id, string Name);
}
