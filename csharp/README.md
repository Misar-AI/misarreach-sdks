# MisarReach .NET SDK

Official C# SDK for [MisarReach](https://reach.misar.io) — lead finder
(23 sources), multi-channel outreach, and CRM (deals, pipeline, sales agents).

Authenticates with a `mrk_` API key against `https://api.misar.io/reach/api`.
Targets .NET 8, `System.Text.Json`, async/await.

## Install

```bash
dotnet add package Misar.Reach
```

## Usage

```csharp
using Misar.Reach;

using var client = new MisarReachClient("mrk_...");

// Start an async lead search
var job = await client.Leads_SearchAsync(new { query = "saas founders", limit = 25 });

// Poll the job
var status = await client.Leads_JobStatusAsync(job.GetProperty("jobId").GetString()!);

// Enrich / verify / score
await client.Leads_EnrichAsync(new { email = "jane@acme.com" });
await client.Leads_VerifyEmailsAsync(new { emails = new[] { "a@b.com" } });

// CRM
await client.Deals_CreateAsync(new { title = "Acme", value = 5000 });
var pipeline = await client.Pipeline_GetAsync();

// Multi-channel outreach
var channels = await client.Channels_StatusAsync();
await client.Channels_ConnectSmsAsync(new { number = "+1..." });
```

### Live lead-search stream (Server-Sent Events)

```csharp
await client.Leads_StreamJobAsync(jobId, async e =>
{
    switch (e.Event)
    {
        case "progress": Console.WriteLine($"found: {e.Data.GetProperty("total_found")}"); break;
        case "complete": Console.WriteLine("done"); break;
        case "error":    Console.WriteLine($"error: {e.Data.GetProperty("error")}"); break;
    }
    await Task.CompletedTask;
});
```

## Methods

Grouped by resource prefix: `Leads_*`, `Ads_*`, `Autopilot_*`, `Campaigns_*`,
`Channels_*`, `Contacts_*`, `Conversations_*`, `Deals_*`, `Pipeline_*`,
`SalesAgent_*`, `Settings_*`, `Workspaces_*` — full coverage of the MisarReach API.

## Errors

Throws typed `MisarReachException` subclasses:

- `AuthException` — 401 / 403
- `NotFoundException` — 404
- `RateLimitException` (`Balance`, `FreeRemaining`) — 429
- `UpgradeRequiredException` — 429 with `upgrade: true`
- `MisarReachNetworkException` — transport failure / retries exhausted
- `MisarReachException` — any other non-2xx (`Status`, `Code`)

Retryable statuses (429, 500, 502, 503, 504) are retried with exponential
back-off (`maxRetries`, default 3).

## License

MIT
