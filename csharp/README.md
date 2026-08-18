# MisarReach .NET SDK

> Async .NET client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![NuGet](https://img.shields.io/nuget/v/Misar.Reach.svg)](https://www.nuget.org/packages/Misar.Reach)
[![Downloads](https://img.shields.io/nuget/dt/Misar.Reach.svg)](https://www.nuget.org/packages/Misar.Reach)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**17 resource groups · 94 operations**

Targets `net8.0` with no third-party dependencies — `System.Text.Json` and
`HttpClient` only. Every call is `async` and returns a `JsonElement`. Unlike the
other SDKs the surface is **flat**: there are no resource sub-objects, just
`Group_MethodAsync` members on `MisarReachClient`. Talks to
`https://api.misar.io/reach/api`.

---

## Install

```bash
dotnet add package Misar.Reach --version 5.0.3
```

Or in your `.csproj`:

```xml
<ItemGroup>
  <PackageReference Include="Misar.Reach" Version="5.0.3" />
</ItemGroup>
```

Targets `net8.0`. No third-party dependencies — `System.Text.Json` and
`HttpClient` only.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```csharp
using Misar.Reach;

using var reach = new MisarReachClient(
    Environment.GetEnvironmentVariable("MISARREACH_API_KEY")!);
```

`MisarReachClient` is `IDisposable`; dispose it (or `using` it) so the
`HttpClient` it owns is released. Pass your own `HttpClient` — from
`IHttpClientFactory`, say — and it will **not** be disposed for you.

---

## Quick start

```csharp
using Misar.Reach;

using var reach = new MisarReachClient(Environment.GetEnvironmentVariable("MISARREACH_API_KEY")!);

var job = await reach.Leads_SearchAsync(new { query = "CTOs at Series A fintech", useAI = true });
string jobId = job.GetProperty("jobId").GetString()!;

var snapshot = await reach.Leads_JobStatusAsync(jobId);
Console.WriteLine($"{snapshot.GetProperty("job").GetProperty("status").GetString()} " +
                  $"{snapshot.GetProperty("results").GetArrayLength()}");
```

To point at the app origin, cap retries differently, or supply your own
`HttpClient` (from `IHttpClientFactory`, say — the client will not dispose one it
did not create):

```csharp
using var pooled = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };

using var pinned = new MisarReachClient(
    apiKey: "mrk_your_key",
    baseUrl: "https://reach.misar.io/api",
    maxRetries: 5,
    httpClient: pooled);
```

---

## What's in the package

- **`MisarReachClient`** — one `sealed class`, `IDisposable`, in namespace
  `Misar.Reach`. Constructed as
  `new MisarReachClient(apiKey, baseUrl = "https://api.misar.io/reach/api", maxRetries = 3, httpClient = null)`.
  Pass your own `HttpClient` (from `IHttpClientFactory`, say) and the client will
  not dispose it; leave it null and the client owns one with a 30-second timeout.
  A blank `apiKey` throws `ArgumentException` at construction.
- **No resource classes.** Unlike the TypeScript, Python, PHP and Rust SDKs,
  nothing hangs off the client as a sub-object: all **94 methods sit directly on
  `MisarReachClient`**, named `Area_OperationAsync` across **17 area prefixes**
  (`Leads_`, `Contacts_`, `Deals_`, `Pipeline_`, `Campaigns_`,
  `CampaignTemplates_`, `Channels_`, `Conversations_`, `SalesAgent_`,
  `Autopilot_`, `Deliverability_`, `Notifications_`, `Webhooks_`, `Workspaces_`,
  `Settings_`, `Ads_`, `Plan_`). That is one method per operation in
  `openapi/reach.openapi.json`, so coverage is complete. Type `client.Leads_` and
  let IntelliSense filter — the prefix is the discovery mechanism a resource
  object would otherwise provide.
- **No typed models.** Request bodies are plain `object` — pass an anonymous
  object and it is serialised with `System.Text.Json`. Responses are
  `JsonElement`, read with `GetProperty(...)`. There is no `Lead`, `Deal` or
  `PlanResponse` record here, unlike the TypeScript and Python SDKs; the trade is
  that the open-shape parts of the API never need an SDK release to reach you.
  Deserialise into your own records with `element.Deserialize<T>()` if you want
  static types.
- **Query strings are raw strings.** Methods that accept filters take a single
  `string? queryParams` appended after `?` — `Leads_ListAsync("page=1&limit=50")`.
  Build it yourself, and `Uri.EscapeDataString` any user-supplied value.
- **`MisarReachStreamEvent`** — a `readonly record struct` with
  `Event` (`string`), `Data` (`JsonElement`) and `Raw` (`string`).
- **Errors** — `MisarReachException` and the typed subclasses below.
- **Transport** — `HttpClient` with a `Bearer` header, and automatic retries with
  exponential back-off starting at 500 ms on 429/500/502/503/504
  (`maxRetries`, default 3, exposed as `MaxRetries`). A plan refusal is *not*
  retried: the retry loop parses the body and skips anything carrying
  `upgrade: true`, so a 429 rate limit and a 429 plan cap are told apart despite
  sharing a status.
- **SSE streaming** for lead-finder job progress, via a **callback**, not
  `IAsyncEnumerable<T>`: `Leads_StreamJobAsync(jobId, ev => …, ct)` returns a
  `Task` that completes when the stream ends. The server sends *named* events —
  `progress`, `found`, `complete`, `error`, `timeout` — plus a `: keepalive`
  comment every 20 seconds, which the parser skips. There is no `[DONE]`
  sentinel; the task simply completes when the server closes the stream. A job
  that has **already finished** is answered with a JSON snapshot rather than a
  stream, and the SDK delivers the terminal `complete`/`error` event in its
  place, so a caller that assumed a stream does not hang on nothing. Streams are
  never retried.

---

## Resources

Every public method, grouped the way the client groups them.

### Lead finder

23-source search, enrichment, verification, scoring, lists and the SSE job stream.

| Method | Description |
|--------|-------------|
| `Leads_AccountAsync()` | Lead-finder credit balance and provider account state. |
| `Leads_ConfigAsync()` | Which sources, filters and AI options this workspace may use. |
| `Leads_ListAsync()` | Saved leads, paginated, newest first. |
| `Leads_ExportAsync()` | Export saved leads as CSV or JSON. |
| `Leads_SearchAsync()` | Start an async search across 23 sources — returns a `jobId`, not leads. |
| `Leads_DiscoverCompaniesAsync()` | Company and lead discovery by firmographic filters. |
| `Leads_EnrichAsync()` | Enrich a saved lead from external data (spends credits). |
| `Leads_VerifyEmailsAsync()` | Verify email deliverability for one address or a batch (spends credits). |
| `Leads_ScoreAsync()` | AI-score leads by job id or an explicit lead-id list. |
| `Leads_JobStatusAsync()` | Poll a search job for status and the results so far. |
| `Leads_SubmitFeedbackAsync()` | Rate a job's results so scoring improves. |
| `Leads_StreamJobAsync()` | SSE progress for a running job — named events, no `[DONE]` sentinel. |
| `Leads_ListLeadListsAsync()` | Lead lists in the workspace. |
| `Leads_CreateLeadListAsync()` | Create a lead list. |
| `Leads_SyncLeadListAsync()` | Sync a lead list to its connected destination. |
| `Leads_SavedSearchesAsync()` | Saved search definitions. |
| `Leads_CreateSavedSearchAsync()` | Save a search for reuse. |
| `Leads_DeleteSavedSearchAsync()` | Delete a saved search. |
| `Leads_ScoringRulesAsync()` | Lead-scoring rules for this workspace. |
| `Leads_CreateScoringRuleAsync()` | Create a lead-scoring rule. |
| `Leads_UpdateScoringRuleAsync()` | Update a lead-scoring rule. |
| `Leads_DeleteScoringRuleAsync()` | Delete a lead-scoring rule. |
| `Leads_RecommendationsAsync()` | Suggested next leads based on what you have already saved. |
| `Leads_SearchHistoryAsync()` | Past searches with their result counts. |
| `Leads_PreviewMessageAsync()` | Draft the AI outreach message for a lead without sending it. |
| `Leads_SendToCampaignAsync()` | Push selected leads into an existing campaign. |
| `Leads_AddToSegmentAsync()` | Add selected leads to a contact segment. |
| `Leads_CompanyAsync()` | Company profile for a domain. |
| `Leads_CompanyPeopleAsync()` | People found at that company. |

### Deals

CRM deals, their activity log and AI next steps.

| Method | Description |
|--------|-------------|
| `Deals_ListAsync()` | List CRM deals with a workspace revenue summary. |
| `Deals_CreateAsync()` | Create a CRM deal. |
| `Deals_UpdateAsync()` | Update a deal. |
| `Deals_DeleteAsync()` | Delete a deal. |
| `Deals_ActivityAsync()` | Activity log for a deal. |
| `Deals_SuggestionsAsync()` | AI next-step suggestions for a deal. |
| `Deals_BulkAsync()` | Delete, move or tag many deals at once; tag writes are atomic server-side. |

### Pipeline

The Kanban board and stage moves.

| Method | Description |
|--------|-------------|
| `Pipeline_GetAsync()` | Kanban board of deals grouped by stage, with revenue totals. |
| `Pipeline_CreateAsync()` | Move a deal to another stage. |

### Campaigns

Multi-step sequences and recipient dispatch.

| Method | Description |
|--------|-------------|
| `Campaigns_ListAsync()` | List campaigns with step counts and send-status summaries. |
| `Campaigns_CreateAsync()` | Create a campaign with an optional step sequence. |
| `Campaigns_GetAsync()` | Read one campaign. |
| `Campaigns_UpdateAsync()` | Update a campaign. |
| `Campaigns_DeleteAsync()` | Delete a campaign. |
| `Campaigns_EnqueueAsync()` | Queue recipients; check `warnings` for steps that can never deliver. |

### Campaign templates

Reusable starting points.

| Method | Description |
|--------|-------------|
| `CampaignTemplates_ListAsync()` | Built-in templates plus your saved ones. |
| `CampaignTemplates_CreateAsync()` | Save a template from steps or by copying a campaign. |

### Contacts

The audience behind outreach.

| Method | Description |
|--------|-------------|
| `Contacts_ListAsync()` | List contacts. |
| `Contacts_CreateAsync()` | Create a contact. |
| `Contacts_GetAsync()` | Read one contact. |
| `Contacts_UpdateAsync()` | Update a contact. |
| `Contacts_DeleteAsync()` | Delete a contact. |
| `Contacts_BulkAsync()` | Bulk delete / unsubscribe / resubscribe, max 500. |
| `Contacts_ImportAsync()` | Import up to 5000 contacts; `subscribed` requires consent evidence. |
| `Contacts_SegmentsAsync()` | Segments defined in the workspace. |
| `Contacts_StatsAsync()` | Audience counts and subscription health. |

### Conversations

The unified inbox.

| Method | Description |
|--------|-------------|
| `Conversations_ListAsync()` | Unified inbox — one row per contact, across every channel. |
| `Conversations_GetAsync()` | One contact's full timeline. |
| `Conversations_ReplyAsync()` | Send a human reply into a thread. |

### Channels

Connectors, consent links and per-channel health.

| Method | Description |
|--------|-------------|
| `Channels_StatusAsync()` | Connection state, credential health and period usage per channel. |
| `Channels_UpdateStatusAsync()` | Enable or disable a channel. |
| `Channels_OptInLinksAsync()` | Double opt-in links to collect SMS/WhatsApp consent. |
| `Channels_ConnectSmsAsync()` | Connect BYO Twilio SMS. |
| `Channels_ConnectWhatsappAsync()` | Connect WhatsApp Business. |
| `Channels_ConnectTelegramAsync()` | Connect a Telegram bot. |
| `Channels_ConnectTwitterAsync()` | Connect X (Twitter) DMs. |
| `Channels_ConnectInstagramAsync()` | Connect Instagram DMs. |
| `Channels_ConnectFacebookAsync()` | Connect Facebook Messenger. |
| `Channels_ConnectDiscordAsync()` | Connect a Discord bot. |
| `Channels_SubscribePushAsync()` | Register a browser web-push subscription. |
| `Channels_UnsubscribePushAsync()` | Unsubscribe this browser from web push. |

### AI sales agent

Config, today's actions, and running the agent over a thread.

| Method | Description |
|--------|-------------|
| `SalesAgent_ActionsAsync()` | What the agent did today. |
| `SalesAgent_ConfigAsync()` | Agent config — offer, booking link, daily reply cap, confidence threshold. |
| `SalesAgent_UpdateConfigAsync()` | Update the agent config. |
| `SalesAgent_ConversationsAsync()` | Conversations the agent is handling. |
| `SalesAgent_ProcessAsync()` | Run the agent over one conversation. |

### Autopilot

Goal-driven runs.

| Method | Description |
|--------|-------------|
| `Autopilot_RunsAsync()` | List autopilot runs, with the caller's plan limits. |
| `Autopilot_StartAsync()` | Start an autopilot run from a stated goal. |
| `Autopilot_GetAsync()` | Read one autopilot run. |
| `Autopilot_StatusAsync()` | Poll a run's status. |
| `Autopilot_SetStatusAsync()` | Pause, resume or stop a run. |

### Deliverability

Sender reputation.

| Method | Description |
|--------|-------------|
| `Deliverability_GetAsync()` | Sender health: bounce and complaint rates against *attempted* sends, plus a verdict. |

### Notifications

The in-app bell.

| Method | Description |
|--------|-------------|
| `Notifications_ListAsync()` | In-app notifications, newest first, with the unread count. |
| `Notifications_MarkReadAsync()` | Mark notifications read — `{ids: [...]}` or `{all: true}`. |

### Webhooks

Signed outbound endpoints.

| Method | Description |
|--------|-------------|
| `Webhooks_ListAsync()` | Registered endpoints and their delivery health. |
| `Webhooks_CreateAsync()` | Register an endpoint; the signing secret is returned once only. |

### Workspaces

Teams and membership.

| Method | Description |
|--------|-------------|
| `Workspaces_ListAsync()` | Workspaces you belong to. |
| `Workspaces_CreateAsync()` | Create a workspace. |
| `Workspaces_ListMembersAsync()` | List members. |
| `Workspaces_AddMemberAsync()` | Invite a member. |
| `Workspaces_RemoveMemberAsync()` | Remove a member. |

### Plan

Caps and usage.

| Method | Description |
|--------|-------------|
| `Plan_GetAsync()` | Plan, caps, per-feature usage and the upgrade offer. |

### Settings

Compliance settings.

| Method | Description |
|--------|-------------|
| `Settings_SenderAddressAsync()` | The CAN-SPAM postal address on file. |
| `Settings_SetSenderAddressAsync()` | Set the CAN-SPAM postal address — sends are blocked until this exists. |

### Ads

Paid-audience export.

| Method | Description |
|--------|-------------|
| `Ads_LinkedinCompanyAudienceAsync()` | Build a LinkedIn company audience from your leads. |

---

## Usage

### Find leads

`Leads_SearchAsync()` returns a job id, not leads — the search runs
asynchronously and answers **202**.

```csharp
var search = await reach.Leads_SearchAsync(new
{
    query = "heads of ops at logistics startups",
    useAI = true,
    filters = new { location = "Berlin", companySize = "11-50" },
});
string searchJobId = search.GetProperty("jobId").GetString()!;
```

### Stream job progress

```csharp
using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(5));

await reach.Leads_StreamJobAsync(searchJobId, ev =>
{
    switch (ev.Event)
    {
        case "progress":
            Console.WriteLine($"working {ev.Data.GetProperty("message").GetString()}");
            break;
        case "found":
            Console.WriteLine($"hit {ev.Data.GetProperty("email").GetString()}");
            break;
        case "complete":
            Console.WriteLine($"done {ev.Data.GetProperty("total_found").GetInt32()}");
            break;
        case "error":
        case "timeout":
            Console.Error.WriteLine($"{ev.Event} {ev.Raw}");
            break;
    }
    return Task.CompletedTask;
}, cts.Token);
```

The callback is `Func<MisarReachStreamEvent, Task>`, so a synchronous body ends
in `return Task.CompletedTask;`. Pass a `CancellationToken` — without one, a
stuck job holds the connection open for as long as the server allows.

### List saved leads

```csharp
var page = await reach.Leads_ListAsync("page=1&limit=50");
Console.WriteLine(page.GetProperty("total").GetInt32());
```

### Create a CRM contact and a deal

```csharp
await reach.Contacts_CreateAsync(new
{
    email = "cto@acme.com",
    firstName = "Dana",
    status = "subscribed",
    consent = new
    {
        source = "signup form /pricing",
        timestamp = DateTime.UtcNow.ToString("o"),
    },
});

var created = await reach.Deals_CreateAsync(new
{
    leadEmail = "cto@acme.com",   // the only required field
    leadName = "Dana Reyes",
    value = 12000,
    currency = "USD",
});
string dealId = created.GetProperty("deal").GetProperty("id").GetString()!;
```

### Read and move the pipeline

```csharp
var pipeline = await reach.Pipeline_GetAsync();
Console.WriteLine($"{pipeline.GetProperty("stages").GetArrayLength()} stages, " +
                  $"{pipeline.GetProperty("revenue").GetProperty("pipeline").GetInt32()} in open pipeline");

// POST /pipeline is the stage move, despite `Create` in the name.
var moved = await reach.Pipeline_CreateAsync(new { dealId, newStage = "meeting" });
```

### Run a campaign

Steps are ordered by their position in the array — the index becomes
`step_order`, so there is no `step_order` field to set. `channel` is the only
required key on a step; `subject` and `body` sit directly on it, not inside a
nested template object.

```csharp
var campaign = await reach.Campaigns_CreateAsync(new
{
    name = "Q3 fintech outbound",
    steps = new object[]
    {
        new { channel = "email", subject = "Quick question", body = "Hi {{name}} …" },
        new { channel = "email", delay_hours = 72, body = "Following up …" },
    },
});
string campaignId = campaign.GetProperty("id").GetString()!;

var result = await reach.Campaigns_EnqueueAsync(campaignId, new
{
    recipients = new object[]
    {
        new { email = "cto@acme.com", name = "Dana Reyes", company = "Acme" },
    },
});

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
Console.WriteLine($"{result.GetProperty("queued").GetInt32()} queued, " +
                  $"{result.GetProperty("skipped").GetInt32()} skipped");
if (result.TryGetProperty("warnings", out var warnings))
    foreach (var w in warnings.EnumerateArray())
        Console.WriteLine($"warning: {w}");
```

### Check the plan before an expensive run

```csharp
using System.Text.Json;

var plan = await reach.Plan_GetAsync();
var searches = plan.GetProperty("usage").GetProperty("lead_searches");

if (searches.GetProperty("remaining").ValueKind == JsonValueKind.Null)
{
    Console.WriteLine($"unlimited lead searches on {plan.GetProperty("plan").GetProperty("name").GetString()}");
}
else if (searches.GetProperty("remaining").GetInt32() == 0)
{
    var offer = plan.GetProperty("upgrade");
    Console.WriteLine($"no searches left; upgrade at {offer.GetProperty("url").GetString()}");
}
```

`usage` is keyed by `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals` and `linkedin_seats`. `upgrade` is `null` until at least one cap
is spent, so check its `ValueKind` before reading `url`.

### Reply into a conversation

```csharp
var inbox = await reach.Conversations_ListAsync("limit=25");

await reach.Conversations_ReplyAsync("cto@acme.com", new
{
    message = "Happy to walk you through it — does Thursday work?",
});
```

The body field is `message` (required, 1–5000 chars); add `conversationId` to
pick a thread other than the contact's most recent. The channel is the thread's,
not yours to choose. The email is URL-escaped into the path for you.

---

## Errors

Every non-2xx throws a `MisarReachException` or one of its subclasses. All live
in the `Misar.Reach` namespace and carry `Status` and `Code`.

| Class | Thrown for |
|-------|-----------|
| `AuthException` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `NotFoundException` | 404 |
| `RateLimitException` | 429 rate limiting; carries `Balance` and `FreeRemaining` |
| `UpgradeRequiredException` | a plan cap was hit — see below |
| `MisarReachNetworkException` | transport failure or retries exhausted; `Status` is 0 |
| `MisarReachException` | any other non-2xx |

The same mapping applies to the SSE stream, so a plan refusal on
`Leads_StreamJobAsync()` throws the same typed exception rather than a bare one.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the exception surfaces immediately:

```csharp
try
{
    await reach.Leads_SearchAsync(new { query = "…" });
}
catch (UpgradeRequiredException err)
{
    // e.g. feature "lead_searches", current 50 of limit 50
    Console.Error.WriteLine($"{err.Feature}: {err.Current}/{err.Limit}");
    Console.Error.WriteLine($"upgrade at {err.UpgradeUrl}");  // resolved to an absolute URL
}
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments — `err.Status` tells you which you got. This is distinct from
the 503 `retry: true` the server sends when it could not *check* the quota: that
body carries no `upgrade` flag, so it is retried, and "we don't know" is never
mistaken for "you're over your limit".

### Reading `remaining`

In `Plan_GetAsync()`, a `usage` entry's `limit` is `null` when the plan is
unlimited for that counter, and `remaining` is `null` alongside it — deliberately
**not** `0`, which would read as exhausted. `JsonElement.GetInt32()` throws on a
JSON null, so test `ValueKind == JsonValueKind.Null` before comparing.

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`Settings_SetSenderAddressAsync()`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **NuGet** — https://www.nuget.org/packages/Misar.Reach

MIT © [Misar AI](https://misar.io)
