using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Misar.Reach;

/// <summary>A single Server-Sent Event emitted by a streaming endpoint.</summary>
public readonly record struct MisarReachStreamEvent(string Event, JsonElement Data, string Raw);

/// <summary>
/// MisarReach API client (C# 10+, System.Text.Json) — lead finder, CRM
/// (deals + pipeline), multi-channel outreach, autopilot, and sales-agent
/// automation.
///
/// Authenticates with a <c>mrk_</c> API key (Bearer) against
/// <c>https://api.misar.io/reach/api</c>. All methods perform up to
/// <see cref="MaxRetries"/> attempts with exponential back-off (starting at
/// 500 ms) on retryable HTTP statuses (429, 500, 502, 503, 504); the final
/// failure is surfaced as a typed <see cref="MisarReachException"/>.
/// </summary>
public sealed class MisarReachClient : IDisposable
{
    private static readonly HashSet<int> RetryableStatuses = [429, 500, 502, 503, 504];

    private readonly string _apiKey;
    private readonly string _baseUrl;
    private readonly int _maxRetries;
    private readonly HttpClient _httpClient;
    private readonly bool _ownsHttpClient;

    public int MaxRetries => _maxRetries;

    public MisarReachClient(
        string apiKey,
        string baseUrl = "https://api.misar.io/reach/api",
        int maxRetries = 3,
        HttpClient? httpClient = null)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new ArgumentException("apiKey must not be blank.", nameof(apiKey));

        _apiKey = apiKey;
        _baseUrl = baseUrl.TrimEnd('/');
        _maxRetries = maxRetries;
        _ownsHttpClient = httpClient is null;
        _httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    }

    // -------------------------------------------------------------------------
    // Core request logic
    // -------------------------------------------------------------------------

    private async Task<JsonElement> RequestAsync(
        HttpMethod method,
        string path,
        object? body = null,
        CancellationToken cancellationToken = default)
    {
        string url = _baseUrl + path;
        string? bodyJson = body is not null ? JsonSerializer.Serialize(body) : null;

        Exception? lastException = null;

        for (int attempt = 0; attempt < _maxRetries; attempt++)
        {
            if (attempt > 0)
            {
                int delayMs = 500 * (1 << (attempt - 1));
                await Task.Delay(delayMs, cancellationToken).ConfigureAwait(false);
            }

            using var request = new HttpRequestMessage(method, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

            if (bodyJson is not null)
                request.Content = new StringContent(bodyJson, Encoding.UTF8, "application/json");

            HttpResponseMessage response;
            try
            {
                response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                lastException = ex;
                continue;
            }

            using (response)
            {
                int status = (int)response.StatusCode;

                if (RetryableStatuses.Contains(status) && attempt < _maxRetries - 1)
                {
                    lastException = new MisarReachException(status, "retryable error");
                    continue;
                }

                string responseBody = await response.Content
                    .ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

                if (response.IsSuccessStatusCode)
                {
                    if (string.IsNullOrWhiteSpace(responseBody))
                        return JsonDocument.Parse("{}").RootElement.Clone();
                    using var doc = JsonDocument.Parse(responseBody);
                    return doc.RootElement.Clone();
                }

                throw MapError(status, responseBody);
            }
        }

        throw new MisarReachNetworkException($"max retries exceeded: {lastException?.Message ?? "unknown"}");
    }

    /// <summary>Maps a non-2xx response into a typed <see cref="MisarReachException"/>.</summary>
    private static MisarReachException MapError(int status, string body)
    {
        string message = string.IsNullOrWhiteSpace(body) ? $"HTTP {status}" : body;
        string? code = null;
        double? balance = null;
        int? freeRemaining = null;
        bool upgrade = false;

        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String)
                    message = e.GetString() ?? message;
                else if (root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
                    message = m.GetString() ?? message;

                if (root.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.String)
                    code = c.GetString();
                if (root.TryGetProperty("balance", out var b) && b.ValueKind == JsonValueKind.Number)
                    balance = b.GetDouble();
                if (root.TryGetProperty("freeRemaining", out var f) && f.ValueKind == JsonValueKind.Number)
                    freeRemaining = f.GetInt32();
                if (root.TryGetProperty("upgrade", out var u) &&
                    (u.ValueKind == JsonValueKind.True || u.ValueKind == JsonValueKind.False))
                    upgrade = u.GetBoolean();
            }
        }
        catch { /* non-JSON body — keep raw message */ }

        return status switch
        {
            401 or 403 => new AuthException(status, message),
            404 => new NotFoundException(message),
            429 when upgrade => new UpgradeRequiredException(message),
            429 => new RateLimitException(message, balance, freeRemaining),
            _ => new MisarReachException(status, message, code),
        };
    }

    // -------------------------------------------------------------------------
    // Server-Sent Events
    // -------------------------------------------------------------------------

    /// <summary>
    /// Opens a Server-Sent Events stream and invokes <paramref name="onEvent"/>
    /// for each event until the stream terminates. If the endpoint returns a
    /// plain JSON snapshot (job already finished), a single synthetic
    /// <c>snapshot</c> event is delivered instead.
    /// </summary>
    private async Task StreamAsync(
        string path,
        Func<MisarReachStreamEvent, Task> onEvent,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, _baseUrl + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/event-stream"));

        using var response = await _httpClient
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);

        if (!response.IsSuccessStatusCode)
        {
            string errBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw MapError((int)response.StatusCode, errBody);
        }

        string? mediaType = response.Content.Headers.ContentType?.MediaType;
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);

        // Non-stream fallback: server returned a JSON snapshot.
        if (mediaType is not null && !mediaType.Contains("event-stream", StringComparison.OrdinalIgnoreCase))
        {
            using var sr = new StreamReader(stream);
            string snapshot = await sr.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            await onEvent(new MisarReachStreamEvent("snapshot", ParseData(snapshot), snapshot)).ConfigureAwait(false);
            return;
        }

        using var reader = new StreamReader(stream);
        string eventName = "message";
        var dataLines = new List<string>();

        async Task Dispatch()
        {
            if (dataLines.Count == 0) { eventName = "message"; return; }
            string raw = string.Join("\n", dataLines);
            await onEvent(new MisarReachStreamEvent(eventName, ParseData(raw), raw)).ConfigureAwait(false);
            eventName = "message";
            dataLines.Clear();
        }

        string? line;
        while ((line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false)) is not null)
        {
            if (line.Length == 0)
                await Dispatch().ConfigureAwait(false);
            else if (line.StartsWith(':'))
                continue; // comment / heartbeat
            else if (line.StartsWith("event:", StringComparison.Ordinal))
                eventName = line[6..].Trim();
            else if (line.StartsWith("data:", StringComparison.Ordinal))
                dataLines.Add(line[5..].Trim());
        }
        await Dispatch().ConfigureAwait(false);
    }

    private static JsonElement ParseData(string raw)
    {
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            return doc.RootElement.Clone();
        }
        catch
        {
            using var doc = JsonDocument.Parse("{}");
            return doc.RootElement.Clone();
        }
    }

    private static string Q(string? queryParams, string basePath) =>
        string.IsNullOrEmpty(queryParams) ? basePath : $"{basePath}?{queryParams}";

    // =========================================================================
    // Lead Finder
    // =========================================================================

    /// <summary>GET /lead-finder/account</summary>
    public Task<JsonElement> Leads_AccountAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/lead-finder/account", cancellationToken: ct);

    /// <summary>GET /lead-finder/config</summary>
    public Task<JsonElement> Leads_ConfigAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/lead-finder/config", cancellationToken: ct);

    /// <summary>GET /lead-finder/leads</summary>
    public Task<JsonElement> Leads_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/lead-finder/leads"), cancellationToken: ct);

    /// <summary>GET /lead-finder/export</summary>
    public Task<JsonElement> Leads_ExportAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/lead-finder/export"), cancellationToken: ct);

    /// <summary>POST /lead-finder/search</summary>
    public Task<JsonElement> Leads_SearchAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/search", payload, ct);

    /// <summary>POST /lead-finder/discover</summary>
    public Task<JsonElement> Leads_DiscoverCompaniesAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/discover", payload, ct);

    /// <summary>POST /lead-finder/enrich</summary>
    public Task<JsonElement> Leads_EnrichAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/enrich", payload, ct);

    /// <summary>POST /lead-finder/verify</summary>
    public Task<JsonElement> Leads_VerifyEmailsAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/verify", payload, ct);

    /// <summary>POST /lead-finder/score</summary>
    public Task<JsonElement> Leads_ScoreAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/score", payload, ct);

    /// <summary>GET /lead-finder/jobs/{jobId}</summary>
    public Task<JsonElement> Leads_JobStatusAsync(string jobId, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/lead-finder/jobs/{jobId}", cancellationToken: ct);

    /// <summary>POST /lead-finder/jobs/{jobId}/feedback</summary>
    public Task<JsonElement> Leads_SubmitFeedbackAsync(string jobId, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/lead-finder/jobs/{jobId}/feedback", payload, ct);

    /// <summary>GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events live progress.</summary>
    public Task Leads_StreamJobAsync(string jobId, Func<MisarReachStreamEvent, Task> onEvent, CancellationToken ct = default) =>
        StreamAsync($"/lead-finder/jobs/{jobId}/stream", onEvent, ct);

    /// <summary>GET /lead-finder/lists</summary>
    public Task<JsonElement> Leads_ListLeadListsAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/lead-finder/lists", cancellationToken: ct);

    /// <summary>POST /lead-finder/lists</summary>
    public Task<JsonElement> Leads_CreateLeadListAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/lists", payload, ct);

    /// <summary>POST /lead-finder/lists/{listId}/sync</summary>
    public Task<JsonElement> Leads_SyncLeadListAsync(string listId, object? payload = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/lead-finder/lists/{listId}/sync", payload, ct);

    /// <summary>GET /lead-finder/saved-searches</summary>
    public Task<JsonElement> Leads_SavedSearchesAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/lead-finder/saved-searches", cancellationToken: ct);

    /// <summary>POST /lead-finder/saved-searches</summary>
    public Task<JsonElement> Leads_CreateSavedSearchAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/saved-searches", payload, ct);

    /// <summary>DELETE /lead-finder/saved-searches/{id}</summary>
    public Task<JsonElement> Leads_DeleteSavedSearchAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, $"/lead-finder/saved-searches/{id}", cancellationToken: ct);

    /// <summary>GET /lead-finder/scoring-rules</summary>
    public Task<JsonElement> Leads_ScoringRulesAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/lead-finder/scoring-rules", cancellationToken: ct);

    /// <summary>POST /lead-finder/scoring-rules</summary>
    public Task<JsonElement> Leads_CreateScoringRuleAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/scoring-rules", payload, ct);

    /// <summary>PATCH /lead-finder/scoring-rules/{id}</summary>
    public Task<JsonElement> Leads_UpdateScoringRuleAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, $"/lead-finder/scoring-rules/{id}", payload, ct);

    /// <summary>DELETE /lead-finder/scoring-rules/{id}</summary>
    public Task<JsonElement> Leads_DeleteScoringRuleAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, $"/lead-finder/scoring-rules/{id}", cancellationToken: ct);

    /// <summary>GET /lead-finder/recommendations</summary>
    public Task<JsonElement> Leads_RecommendationsAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/lead-finder/recommendations"), cancellationToken: ct);

    /// <summary>GET /lead-finder/search-history</summary>
    public Task<JsonElement> Leads_SearchHistoryAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/lead-finder/search-history"), cancellationToken: ct);

    /// <summary>POST /lead-finder/preview-message — public, no auth required.</summary>
    public Task<JsonElement> Leads_PreviewMessageAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/preview-message", payload, ct);

    /// <summary>POST /lead-finder/send-to-campaign</summary>
    public Task<JsonElement> Leads_SendToCampaignAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/send-to-campaign", payload, ct);

    /// <summary>POST /lead-finder/add-to-segment</summary>
    public Task<JsonElement> Leads_AddToSegmentAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/lead-finder/add-to-segment", payload, ct);

    /// <summary>GET /lead-finder/companies/{domain}</summary>
    public Task<JsonElement> Leads_CompanyAsync(string domain, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/lead-finder/companies/{domain}", cancellationToken: ct);

    /// <summary>GET /lead-finder/companies/{domain}/people</summary>
    public Task<JsonElement> Leads_CompanyPeopleAsync(string domain, string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, $"/lead-finder/companies/{domain}/people"), cancellationToken: ct);

    // =========================================================================
    // Ads
    // =========================================================================

    /// <summary>POST /ads/linkedin/company-audience</summary>
    public Task<JsonElement> Ads_LinkedinCompanyAudienceAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/ads/linkedin/company-audience", payload, ct);

    // =========================================================================
    // Autopilot
    // =========================================================================

    /// <summary>GET /autopilot/runs</summary>
    public Task<JsonElement> Autopilot_RunsAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/autopilot/runs"), cancellationToken: ct);

    /// <summary>POST /autopilot/start</summary>
    public Task<JsonElement> Autopilot_StartAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/autopilot/start", payload, ct);

    /// <summary>GET /autopilot/{id}</summary>
    public Task<JsonElement> Autopilot_GetAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/autopilot/{id}", cancellationToken: ct);

    /// <summary>GET /autopilot/{id}/status</summary>
    public Task<JsonElement> Autopilot_StatusAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/autopilot/{id}/status", cancellationToken: ct);

    /// <summary>POST /autopilot/{id}/status</summary>
    public Task<JsonElement> Autopilot_SetStatusAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/autopilot/{id}/status", payload, ct);

    // =========================================================================
    // Campaigns
    // =========================================================================

    /// <summary>GET /campaigns</summary>
    public Task<JsonElement> Campaigns_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/campaigns"), cancellationToken: ct);

    /// <summary>POST /campaigns</summary>
    public Task<JsonElement> Campaigns_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/campaigns", payload, ct);

    /// <summary>GET /campaigns/{id}</summary>
    public Task<JsonElement> Campaigns_GetAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/campaigns/{id}", cancellationToken: ct);

    /// <summary>PATCH /campaigns/{id}</summary>
    public Task<JsonElement> Campaigns_UpdateAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, $"/campaigns/{id}", payload, ct);

    /// <summary>DELETE /campaigns/{id}</summary>
    public Task<JsonElement> Campaigns_DeleteAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, $"/campaigns/{id}", cancellationToken: ct);

    /// <summary>POST /campaigns/{id}/enqueue</summary>
    public Task<JsonElement> Campaigns_EnqueueAsync(string id, object? payload = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/campaigns/{id}/enqueue", payload, ct);

    // =========================================================================
    // Channels
    // =========================================================================

    /// <summary>GET /channels/status</summary>
    public Task<JsonElement> Channels_StatusAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/channels/status", cancellationToken: ct);

    /// <summary>PATCH /channels/status</summary>
    public Task<JsonElement> Channels_UpdateStatusAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, "/channels/status", payload, ct);

    /// <summary>GET /channels/opt-in-links</summary>
    public Task<JsonElement> Channels_OptInLinksAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/channels/opt-in-links"), cancellationToken: ct);

    /// <summary>POST /channels/sms/connect</summary>
    public Task<JsonElement> Channels_ConnectSmsAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/sms/connect", payload, ct);

    /// <summary>POST /channels/whatsapp/connect</summary>
    public Task<JsonElement> Channels_ConnectWhatsappAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/whatsapp/connect", payload, ct);

    /// <summary>POST /channels/telegram/connect</summary>
    public Task<JsonElement> Channels_ConnectTelegramAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/telegram/connect", payload, ct);

    /// <summary>POST /channels/twitter/connect</summary>
    public Task<JsonElement> Channels_ConnectTwitterAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/twitter/connect", payload, ct);

    /// <summary>POST /channels/instagram/connect</summary>
    public Task<JsonElement> Channels_ConnectInstagramAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/instagram/connect", payload, ct);

    /// <summary>POST /channels/facebook/connect</summary>
    public Task<JsonElement> Channels_ConnectFacebookAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/facebook/connect", payload, ct);

    /// <summary>POST /channels/discord/connect</summary>
    public Task<JsonElement> Channels_ConnectDiscordAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/discord/connect", payload, ct);

    /// <summary>POST /channels/push/subscribe</summary>
    public Task<JsonElement> Channels_SubscribePushAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/channels/push/subscribe", payload, ct);

    /// <summary>DELETE /channels/push/subscribe</summary>
    public Task<JsonElement> Channels_UnsubscribePushAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, "/channels/push/subscribe", cancellationToken: ct);

    // =========================================================================
    // Contacts
    // =========================================================================

    /// <summary>GET /contacts</summary>
    public Task<JsonElement> Contacts_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/contacts"), cancellationToken: ct);

    /// <summary>POST /contacts</summary>
    public Task<JsonElement> Contacts_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/contacts", payload, ct);

    /// <summary>GET /contacts/{id}</summary>
    public Task<JsonElement> Contacts_GetAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/contacts/{id}", cancellationToken: ct);

    /// <summary>PATCH /contacts/{id}</summary>
    public Task<JsonElement> Contacts_UpdateAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, $"/contacts/{id}", payload, ct);

    /// <summary>DELETE /contacts/{id}</summary>
    public Task<JsonElement> Contacts_DeleteAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, $"/contacts/{id}", cancellationToken: ct);

    /// <summary>POST /contacts/bulk</summary>
    public Task<JsonElement> Contacts_BulkAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/contacts/bulk", payload, ct);

    /// <summary>POST /contacts/import</summary>
    public Task<JsonElement> Contacts_ImportAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/contacts/import", payload, ct);

    /// <summary>GET /contacts/segments</summary>
    public Task<JsonElement> Contacts_SegmentsAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/contacts/segments", cancellationToken: ct);

    /// <summary>GET /contacts/stats</summary>
    public Task<JsonElement> Contacts_StatsAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/contacts/stats", cancellationToken: ct);

    // =========================================================================
    // Conversations
    // =========================================================================

    /// <summary>GET /conversations</summary>
    public Task<JsonElement> Conversations_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/conversations"), cancellationToken: ct);

    /// <summary>GET /conversations/{email}</summary>
    public Task<JsonElement> Conversations_GetAsync(string email, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/conversations/{Uri.EscapeDataString(email)}", cancellationToken: ct);

    // =========================================================================
    // Deals
    // =========================================================================

    /// <summary>GET /deals</summary>
    public Task<JsonElement> Deals_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/deals"), cancellationToken: ct);

    /// <summary>POST /deals</summary>
    public Task<JsonElement> Deals_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/deals", payload, ct);

    /// <summary>PATCH /deals/{id}</summary>
    public Task<JsonElement> Deals_UpdateAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, $"/deals/{id}", payload, ct);

    /// <summary>DELETE /deals/{id}</summary>
    public Task<JsonElement> Deals_DeleteAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, $"/deals/{id}", cancellationToken: ct);

    /// <summary>GET /deals/{id}/activity</summary>
    public Task<JsonElement> Deals_ActivityAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/deals/{id}/activity", cancellationToken: ct);

    /// <summary>GET /deals/{id}/suggestions</summary>
    public Task<JsonElement> Deals_SuggestionsAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/deals/{id}/suggestions", cancellationToken: ct);

    /// <summary>
    /// POST /deals/bulk — one operation over many deals,
    /// {"ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...}. Tag writes are
    /// applied atomically server-side, so concurrent callers cannot lose a tag.
    /// </summary>
    public Task<JsonElement> Deals_BulkAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/deals/bulk", payload, cancellationToken: ct);

    // =========================================================================
    // Pipeline
    // =========================================================================

    /// <summary>GET /pipeline</summary>
    public Task<JsonElement> Pipeline_GetAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/pipeline", cancellationToken: ct);

    /// <summary>POST /pipeline</summary>
    public Task<JsonElement> Pipeline_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/pipeline", payload, ct);

    // =========================================================================
    // Sales Agent
    // =========================================================================

    /// <summary>GET /sales-agent/actions</summary>
    public Task<JsonElement> SalesAgent_ActionsAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/sales-agent/actions"), cancellationToken: ct);

    /// <summary>GET /sales-agent/config</summary>
    public Task<JsonElement> SalesAgent_ConfigAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/sales-agent/config", cancellationToken: ct);

    /// <summary>PATCH /sales-agent/config</summary>
    public Task<JsonElement> SalesAgent_UpdateConfigAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, "/sales-agent/config", payload, ct);

    /// <summary>GET /sales-agent/conversations</summary>
    public Task<JsonElement> SalesAgent_ConversationsAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/sales-agent/conversations"), cancellationToken: ct);

    /// <summary>POST /sales-agent/process</summary>
    public Task<JsonElement> SalesAgent_ProcessAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/sales-agent/process", payload, ct);

    // =========================================================================
    // Settings
    // =========================================================================

    /// <summary>GET /settings/sender-address</summary>
    public Task<JsonElement> Settings_SenderAddressAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/settings/sender-address", cancellationToken: ct);

    /// <summary>PUT /settings/sender-address</summary>
    public Task<JsonElement> Settings_SetSenderAddressAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Put, "/settings/sender-address", payload, ct);

    // =========================================================================
    // Workspaces
    // =========================================================================

    /// <summary>GET /workspaces</summary>
    public Task<JsonElement> Workspaces_ListAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/workspaces", cancellationToken: ct);

    /// <summary>POST /workspaces</summary>
    public Task<JsonElement> Workspaces_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/workspaces", payload, ct);

    /// <summary>GET /workspaces/{id}/members</summary>
    public Task<JsonElement> Workspaces_ListMembersAsync(string id, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, $"/workspaces/{id}/members", cancellationToken: ct);

    /// <summary>POST /workspaces/{id}/members</summary>
    public Task<JsonElement> Workspaces_AddMemberAsync(string id, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/workspaces/{id}/members", payload, ct);

    /// <summary>DELETE /workspaces/{id}/members</summary>
    public Task<JsonElement> Workspaces_RemoveMemberAsync(string id, string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Delete, Q(queryParams, $"/workspaces/{id}/members"), cancellationToken: ct);

    /// <summary>POST /conversations/{email}/reply</summary>
    public Task<JsonElement> Conversations_ReplyAsync(string email, object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, $"/conversations/{Uri.EscapeDataString(email)}/reply", payload, cancellationToken: ct);

    // -------------------------------------------------------------------------
    // Campaign templates
    // -------------------------------------------------------------------------

    /// <summary>GET /campaign-templates</summary>
    public Task<JsonElement> CampaignTemplates_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/campaign-templates"), cancellationToken: ct);

    /// <summary>POST /campaign-templates</summary>
    public Task<JsonElement> CampaignTemplates_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/campaign-templates", payload, cancellationToken: ct);

    // -------------------------------------------------------------------------
    // Deliverability
    // -------------------------------------------------------------------------

    /// <summary>
    /// GET /deliverability — sender health. bounceRate and complaintRate are null
    /// when there is not enough volume to judge, which is not the same as zero.
    /// </summary>
    public Task<JsonElement> Deliverability_GetAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/deliverability"), cancellationToken: ct);

    // -------------------------------------------------------------------------
    // Notifications
    // -------------------------------------------------------------------------

    /// <summary>GET /notifications</summary>
    public Task<JsonElement> Notifications_ListAsync(string? queryParams = null, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, Q(queryParams, "/notifications"), cancellationToken: ct);

    /// <summary>PATCH /notifications — pass {"ids": [...]} or {"all": true}.</summary>
    public Task<JsonElement> Notifications_MarkReadAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Patch, "/notifications", payload, cancellationToken: ct);

    // -------------------------------------------------------------------------
    // Webhooks
    // -------------------------------------------------------------------------

    /// <summary>GET /webhooks/endpoints</summary>
    public Task<JsonElement> Webhooks_ListAsync(CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Get, "/webhooks/endpoints", cancellationToken: ct);

    /// <summary>
    /// POST /webhooks/endpoints — the response carries the signing secret exactly
    /// once; store it then, it is not retrievable afterwards.
    /// </summary>
    public Task<JsonElement> Webhooks_CreateAsync(object payload, CancellationToken ct = default) =>
        RequestAsync(HttpMethod.Post, "/webhooks/endpoints", payload, cancellationToken: ct);

    // -------------------------------------------------------------------------
    // IDisposable
    // -------------------------------------------------------------------------

    public void Dispose()
    {
        if (_ownsHttpClient)
            _httpClient.Dispose();
    }
}
