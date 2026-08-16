using System.Net;
using System.Text;
using System.Text.Json;
using Misar.Reach;
using Xunit;

namespace Misar.Reach.Tests;

/// <summary>
/// Unit tests for <see cref="MisarReachClient"/>.
///
/// A <see cref="StubHttpMessageHandler"/> replaces the real <see cref="HttpClient"/>
/// transport so no network calls are made.
/// </summary>
public sealed class MisarReachClientTests
{
    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        private readonly int _statusCode;
        private readonly string _body;
        public HttpRequestMessage? LastRequest { get; private set; }

        public StubHttpMessageHandler(int statusCode, string body)
        {
            _statusCode = statusCode;
            _body = body;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequest = request;
            var response = new HttpResponseMessage((HttpStatusCode)_statusCode)
            {
                Content = new StringContent(_body, Encoding.UTF8, "application/json")
            };
            return Task.FromResult(response);
        }
    }

    private static (MisarReachClient client, StubHttpMessageHandler handler) ClientWith(int status, string body)
    {
        var handler = new StubHttpMessageHandler(status, body);
        var httpClient = new HttpClient(handler);
        var client = new MisarReachClient(apiKey: "mrk_test_key", maxRetries: 1, httpClient: httpClient);
        return (client, handler);
    }

    [Fact]
    public async Task LeadsSearch_200_ReturnsParsedResponse()
    {
        var (client, handler) = ClientWith(200, """{"jobId":"job_1","status":"running"}""");
        using (client)
        {
            var result = await client.Leads_SearchAsync(new { query = "saas founders" });
            Assert.Equal("job_1", result.GetProperty("jobId").GetString());
            Assert.Equal("/reach/api/lead-finder/search", handler.LastRequest!.RequestUri!.AbsolutePath);
        }
    }

    [Fact]
    public async Task LeadsList_200_ReturnsParsedResponse()
    {
        var (client, _) = ClientWith(200, """{"data":[],"total":0}""");
        using (client)
        {
            var result = await client.Leads_ListAsync("page=1&limit=20");
            Assert.True(result.TryGetProperty("data", out _));
        }
    }

    [Fact]
    public async Task DealsCreate_201_ReturnsParsedResponse()
    {
        var (client, _) = ClientWith(201, """{"id":"deal_1","title":"Acme"}""");
        using (client)
        {
            var result = await client.Deals_CreateAsync(new { title = "Acme" });
            Assert.Equal("deal_1", result.GetProperty("id").GetString());
        }
    }

    [Fact]
    public async Task ChannelsStatus_200_ReturnsParsedResponse()
    {
        var (client, _) = ClientWith(200, """{"sms":true,"whatsapp":false}""");
        using (client)
        {
            var result = await client.Channels_StatusAsync();
            Assert.True(result.GetProperty("sms").GetBoolean());
        }
    }

    [Fact]
    public async Task PipelineGet_200_ReturnsParsedResponse()
    {
        var (client, _) = ClientWith(200, """{"stages":[]}""");
        using (client)
        {
            var result = await client.Pipeline_GetAsync();
            Assert.True(result.TryGetProperty("stages", out _));
        }
    }

    [Fact]
    public async Task PreviewMessage_200_ReturnsParsedResponse()
    {
        var (client, _) = ClientWith(200, """{"message":"Hi there"}""");
        using (client)
        {
            var result = await client.Leads_PreviewMessageAsync(new { lead = new { name = "Jane" } });
            Assert.Equal("Hi there", result.GetProperty("message").GetString());
        }
    }

    [Fact]
    public async Task Status401_ThrowsAuthException()
    {
        var (client, _) = ClientWith(401, """{"error":"Unauthorized"}""");
        using (client)
        {
            var ex = await Assert.ThrowsAsync<AuthException>(() => client.Leads_SearchAsync(new { query = "x" }));
            Assert.Equal(401, ex.Status);
        }
    }

    [Fact]
    public async Task Status404_ThrowsNotFoundException()
    {
        var (client, _) = ClientWith(404, """{"error":"not found"}""");
        using (client)
        {
            var ex = await Assert.ThrowsAsync<NotFoundException>(() => client.Deals_ActivityAsync("missing"));
            Assert.Equal(404, ex.Status);
        }
    }

    [Fact]
    public async Task Status429_ThrowsRateLimitException_WithFields()
    {
        var (client, _) = ClientWith(429, """{"error":"rate limited","balance":12.5,"freeRemaining":3}""");
        using (client)
        {
            var ex = await Assert.ThrowsAsync<RateLimitException>(() => client.Leads_EnrichAsync(new { email = "a@b.com" }));
            Assert.Equal(12.5, ex.Balance);
            Assert.Equal(3, ex.FreeRemaining);
        }
    }

    [Fact]
    public async Task Status429_Upgrade_ThrowsUpgradeRequiredException()
    {
        var (client, _) = ClientWith(429, """{"error":"upgrade","upgrade":true}""");
        using (client)
        {
            await Assert.ThrowsAsync<UpgradeRequiredException>(() => client.Leads_ScoreAsync(new { jobId = "j1" }));
        }
    }

    [Fact]
    public async Task EmptyBody_200_ReturnsEmptyJsonObject()
    {
        var (client, _) = ClientWith(200, "");
        using (client)
        {
            var result = await client.Contacts_StatsAsync();
            Assert.Equal(JsonValueKind.Object, result.ValueKind);
        }
    }

    [Fact]
    public void Constructor_BlankApiKey_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() => new MisarReachClient(""));
    }
}
