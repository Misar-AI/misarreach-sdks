# MisarReach Java SDK

> Java client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![Java 17+](https://img.shields.io/badge/Java-17%2B-orange.svg)](https://adoptium.net/)
[![Maven Central](https://img.shields.io/badge/Maven%20Central-io.misar%3Amisarreach--java-blue.svg)](https://central.sonatype.com/artifact/io.misar/misarreach-java)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**18 resource groups · 94 operations**

Requires Java 17+. HTTP comes from the JDK's own `HttpClient`, so nothing pulls
OkHttp or Apache HttpClient onto your classpath; the one declared runtime
dependency is `jackson-databind`. Blocking calls throughout, with
`CompletableFuture` twins on the busiest 30 — 136 public methods in all, over
the same 94 operations. Talks to `https://api.misar.io/reach/api`.

---

## Install

Maven:

```xml
<dependency>
    <groupId>io.misar</groupId>
    <artifactId>misarreach-java</artifactId>
    <version>5.0.3</version>
</dependency>
```

Gradle (Kotlin or Groovy DSL):

```kotlin
implementation("io.misar:misarreach-java:5.0.3")
```

Requires Java 17+. The only declared runtime dependency is
`com.fasterxml.jackson.core:jackson-databind:2.17.1` (which pulls in
`jackson-core` and `jackson-annotations`); HTTP comes from the JDK, so there is
no OkHttp or Apache HttpClient on your classpath because of this artifact.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```java
import io.misar.reach.MisarReachClient;

MisarReachClient client =
        new MisarReachClient.Builder(System.getenv("MISARREACH_API_KEY")).build();
```

The API key is the `Builder`'s only required argument. A blank or null key
throws `IllegalArgumentException` from the `Builder` constructor — before
`build()`, and long before a 401 on the first call.

---

## Quick start

```java
import io.misar.reach.MisarReachClient;
import io.misar.reach.MisarReachException;

import java.util.List;
import java.util.Map;

public class Quickstart {
    public static void main(String[] args) throws MisarReachException {
        // The API key is the Builder's only required argument.
        MisarReachClient client =
                new MisarReachClient.Builder(System.getenv("MISARREACH_API_KEY")).build();

        Map<String, Object> started = client.leads.search(Map.of(
                "query", "CTOs at Series A fintech",
                "useAI", true));
        String jobId = (String) started.get("jobId");

        Map<String, Object> snapshot = client.leads.job(jobId);
        Map<?, ?> job = (Map<?, ?>) snapshot.get("job");
        System.out.println(job.get("status") + " " + ((List<?>) snapshot.get("results")).size());
    }
}
```

### Configuring the client

```java
MisarReachClient client = new MisarReachClient.Builder("mrk_your_key")
        .baseUrl("https://reach.misar.io/api")   // default https://api.misar.io/reach/api
        .maxRetries(5)                           // default 3; this is a TOTAL attempt count
        .httpClient(HttpClient.newHttpClient())  // bring your own proxy, executor or redirect policy
        .build();
```

`maxRetries` counts attempts, not retries after the first: `maxRetries(1)` sends
one request and never retries, and `maxRetries(0)` sends **nothing** and throws
`Max retries exceeded`. A trailing `/` on `baseUrl` is stripped for you.

---

## What's in the package

- `MisarReachClient` — built through `MisarReachClient.Builder`, never `new`.
  The 18 resource groups are `public final` fields on the instance, so it is
  `client.leads.search(…)`, not `client.leads().search(…)`.
- **Resource classes**, all inner classes of `MisarReachClient` and reachable as
  types (`MisarReachClient.LeadsResource`) if you want to pass one around:
  `LeadsResource`, `LeadFinderResource`, `DealsResource`, `PipelineResource`,
  `CampaignsResource`, `CampaignTemplatesResource`, `ContactsResource`,
  `ConversationsResource`, `ChannelsResource`, `SalesAgentResource`,
  `AutopilotResource`, `DeliverabilityResource`, `NotificationsResource`,
  `WebhooksResource`, `WorkspacesResource`, `SettingsResource`, `AdsResource`,
  `PlanResource` — 136 public methods between them, covering all 94 operations
  in `openapi/reach.openapi.json`.
- **No typed models.** Unlike the TypeScript SDK, every request body and every
  response is a plain `Map<String, Object>`, serialised by Jackson
  (`jackson-databind`). Nested objects are `Map<?, ?>`, arrays are `List<?>`,
  JSON `null` is Java `null`, and JSON integers arrive as `Integer`/`Long`.
  Cast at the point of use.
- `MisarReachClient.SseEvent` — a `record (String event, Map<String,Object> data,
  String raw)`. Accessors are `event()`, `data()` and `raw()`, not getters.
  `data()` is `null` when a frame was not JSON; `raw()` always carries the
  payload as received.
- **Errors** — two types only: `MisarReachException` and `UpgradeRequiredException`.
  See [Errors](#errors); there is deliberately no `AuthException` or
  `NotFoundException` to catch.
- **Transport** — the JDK's `java.net.http.HttpClient` with a `Bearer` header, a
  10s connect timeout on the default client and a 30s timeout on every request
  except the SSE stream, which is deliberately untimed. It **does** retry, with
  exponential back-off from 500 ms (500, 1000, 2000 …), on 429/500/502/503/504
  (`maxRetries`, default 3). A 402 plan refusal is never retried; nor is a 429
  carrying `upgrade: true`, which the retry loop inspects the body to tell apart
  from genuine rate limiting.
- **Blocking by default, with `*Async` twins on the busiest calls.** 30 of the
  136 methods have a `CompletableFuture` variant (`searchAsync`, `listAsync`,
  `createAsync`, …). The rest are synchronous only — this is *not* a client
  where every method has an async form, so check for the twin before reaching
  for one. Every sync method declares `throws MisarReachException`.
- **SSE streaming** for lead-finder job progress, delivered to a
  `Consumer<SseEvent>` — there is no `Stream`, no `Iterator` and no async twin.
  The server sends *named* events — `progress`, `found`, `complete`, `error`,
  `timeout` — plus a `: keepalive` comment every 20 seconds, which the parser
  drops. There is no `[DONE]` sentinel; the call simply returns when the server
  closes the stream. A job that has **already finished** is answered with a JSON
  snapshot rather than a stream, and the SDK synthesises the terminal
  `complete`/`error` frame from it, so a caller that assumed a stream does not
  hang on nothing.

### Naming to know before you grep

The surface grew in two passes and kept both spellings, so a few names are not
what you would guess:

| You want | Call |
|----------|------|
| list saved leads | `leads.leads(params)` — not `leads.list()` |
| poll a search job | `leads.job(jobId)` — returns `{ job, results }` |
| move a deal's stage | `pipeline.create(…)` — `POST /pipeline` *is* the move |
| read the Kanban board | `pipeline.get(params)` |
| delete a deal/contact/campaign | `delete(id)` or `remove(id)` — same endpoint, `remove` URL-encodes the id |

`client.leadFinder` hits eight endpoints `client.leads` already covers
(`company`, `companyPeople`, `job`, `jobFeedback`, `syncList`,
`removeSavedSearch`, `updateScoringRule`, `removeScoringRule`; the last two map
to `deleteSavedSearch`/`deleteScoringRule` on `leads`). Prefer `client.leads` —
its `companyPeople` takes a query-parameter map, the `leadFinder` one does not.

---

## Resources

Every public method, grouped the way the client groups them.

### Lead finder

23-source search, enrichment, verification, scoring, lists and the SSE job stream.

| Method | Description |
|--------|-------------|
| `account()` | Lead-finder credit balance and provider account state. |
| `config()` | Which sources, filters and AI options this workspace may use. |
| `search()` | Start an async search across 23 sources — returns a `jobId`, not leads. |
| `discover()` | Company and lead discovery by firmographic filters. |
| `enrich()` | Enrich a saved lead from external data (spends credits). |
| `verify()` | Verify email deliverability for one address or a batch (spends credits). |
| `score()` | AI-score leads by job id or an explicit lead-id list. |
| `leads()` | Saved leads, paginated, newest first. |
| `export()` | Export saved leads as CSV or JSON. |
| `recommendations()` | Suggested next leads based on what you have already saved. |
| `searchHistory()` | Past searches with their result counts. |
| `previewMessage()` | Draft the AI outreach message for a lead without sending it. |
| `sendToCampaign()` | Push selected leads into an existing campaign. |
| `addToSegment()` | Add selected leads to a contact segment. |
| `company()` | Company profile for a domain. |
| `companyPeople()` | People found at that company. |
| `job()` | Poll a search job for status and the results so far. |
| `jobFeedback()` | Rate a job's results so scoring improves. |
| `stream()` | SSE progress for a running job — named events, no `[DONE]` sentinel. |
| `lists()` | Lead lists in the workspace. |
| `createList()` | Create a lead list. |
| `syncList()` | Sync a lead list to its connected destination. |
| `savedSearches()` | Saved search definitions. |
| `createSavedSearch()` | Save a search for reuse. |
| `deleteSavedSearch()` | Delete a saved search. |
| `scoringRules()` | Lead-scoring rules for this workspace. |
| `createScoringRule()` | Create a lead-scoring rule. |
| `updateScoringRule()` | Update a lead-scoring rule. |
| `deleteScoringRule()` | Delete a lead-scoring rule. |
| `searchAsync()` | Non-blocking `CompletableFuture` twin of `search()`. |
| `discoverAsync()` | Non-blocking `CompletableFuture` twin of `discover()`. |
| `enrichAsync()` | Non-blocking `CompletableFuture` twin of `enrich()`. |
| `verifyAsync()` | Non-blocking `CompletableFuture` twin of `verify()`. |
| `scoreAsync()` | Non-blocking `CompletableFuture` twin of `score()`. |
| `leadsAsync()` | Non-blocking `CompletableFuture` twin of `leads()`. |

### Deals

CRM deals, their activity log and AI next steps.

| Method | Description |
|--------|-------------|
| `list()` | List CRM deals with a workspace revenue summary. |
| `create()` | Create a CRM deal. |
| `update()` | Update a deal. |
| `delete()` | Delete a deal. |
| `activity()` | Activity log for a deal. |
| `suggestions()` | AI next-step suggestions for a deal. |
| `bulk()` | Delete, move or tag many deals at once; tag writes are atomic server-side. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |
| `updateAsync()` | Non-blocking `CompletableFuture` twin of `update()`. |
| `deleteAsync()` | Non-blocking `CompletableFuture` twin of `delete()`. |
| `remove()` | **Alias of `delete()`** that URL-encodes the id first. Delete a deal. |

### Pipeline

The Kanban board and stage moves.

| Method | Description |
|--------|-------------|
| `get()` | Kanban board of deals grouped by stage, with revenue totals. |
| `create()` | Move a deal to another stage. |
| `getAsync()` | Non-blocking `CompletableFuture` twin of `get()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |

### Campaigns

Multi-step sequences and recipient dispatch.

| Method | Description |
|--------|-------------|
| `list()` | List campaigns with step counts and send-status summaries. |
| `create()` | Create a campaign with an optional step sequence. |
| `get()` | Read one campaign. |
| `update()` | Update a campaign. |
| `delete()` | Delete a campaign. |
| `enqueue()` | Queue recipients; check `warnings` for steps that can never deliver. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |
| `remove()` | **Alias of `delete()`** that URL-encodes the id first. Delete a campaign. |

### Campaign templates

Reusable starting points.

| Method | Description |
|--------|-------------|
| `list()` | Built-in templates plus your saved ones. |
| `create()` | Save a template from steps or by copying a campaign. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |

### Contacts

The audience behind outreach.

| Method | Description |
|--------|-------------|
| `list()` | List contacts. |
| `create()` | Create a contact. |
| `get()` | Read one contact. |
| `update()` | Update a contact. |
| `delete()` | Delete a contact. |
| `bulk()` | Bulk delete / unsubscribe / resubscribe, max 500. |
| `importContacts()` | Import up to 5000 contacts; `subscribed` requires consent evidence. |
| `segments()` | Segments defined in the workspace. |
| `stats()` | Audience counts and subscription health. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |
| `importContactsAsync()` | Non-blocking `CompletableFuture` twin of `importContacts()`. |
| `remove()` | **Alias of `delete()`** that URL-encodes the id first. Delete a contact. |

### Conversations

The unified inbox.

| Method | Description |
|--------|-------------|
| `list()` | Unified inbox — one row per contact, across every channel. |
| `get()` | One contact's full timeline. |
| `reply()` | Send a human reply into a thread. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `replyAsync()` | Non-blocking `CompletableFuture` twin of `reply()`. |

### Channels

Connectors, consent links and per-channel health.

| Method | Description |
|--------|-------------|
| `status()` | Connection state, credential health and period usage per channel. |
| `updateStatus()` | Enable or disable a channel. |
| `optInLinks()` | Double opt-in links to collect SMS/WhatsApp consent. |
| `connectSms()` | Connect BYO Twilio SMS. |
| `connectWhatsapp()` | Connect WhatsApp Business. |
| `connectTelegram()` | Connect a Telegram bot. |
| `connectTwitter()` | Connect X (Twitter) DMs. |
| `connectInstagram()` | Connect Instagram DMs. |
| `connectFacebook()` | Connect Facebook Messenger. |
| `connectDiscord()` | Connect a Discord bot. |
| `subscribePush()` | Register a browser web-push subscription. |
| `unsubscribePush()` | Unsubscribe this browser from web push. |

### AI sales agent

Config, today's actions, and running the agent over a thread.

| Method | Description |
|--------|-------------|
| `config()` | Agent config — offer, booking link, daily reply cap, confidence threshold. |
| `updateConfig()` | Update the agent config. |
| `actions()` | What the agent did today. |
| `conversations()` | Conversations the agent is handling. |
| `process()` | Run the agent over one conversation. |
| `processAsync()` | Non-blocking `CompletableFuture` twin of `process()`. |

### Autopilot

Goal-driven runs.

| Method | Description |
|--------|-------------|
| `start()` | Start an autopilot run from a stated goal. |
| `runs()` | List autopilot runs, with the caller's plan limits. |
| `get()` | Read one autopilot run. |
| `status()` | Poll a run's status. |
| `updateStatus()` | Pause, resume or stop a run. |
| `startAsync()` | Non-blocking `CompletableFuture` twin of `start()`. |
| `runsAsync()` | Non-blocking `CompletableFuture` twin of `runs()`. |
| `setStatus()` | **Alias of `updateStatus()`** that URL-encodes the id first. Pause, resume or stop a run. |

### Deliverability

Sender reputation.

| Method | Description |
|--------|-------------|
| `get()` | Sender health: bounce and complaint rates against *attempted* sends, plus a verdict. |
| `getAsync()` | Non-blocking `CompletableFuture` twin of `get()`. |

### Notifications

The in-app bell.

| Method | Description |
|--------|-------------|
| `list()` | In-app notifications, newest first, with the unread count. |
| `markRead()` | Mark notifications read — `{ids: [...]}` or `{all: true}`. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `markReadAsync()` | Non-blocking `CompletableFuture` twin of `markRead()`. |

### Webhooks

Signed outbound endpoints.

| Method | Description |
|--------|-------------|
| `list()` | Registered endpoints and their delivery health. |
| `create()` | Register an endpoint; the signing secret is returned once only. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |
| `createAsync()` | Non-blocking `CompletableFuture` twin of `create()`. |

### Workspaces

Teams and membership.

| Method | Description |
|--------|-------------|
| `list()` | Workspaces you belong to. |
| `create()` | Create a workspace. |
| `members()` | List members. |
| `addMember()` | Invite a member. |
| `removeMember()` | Remove a member. |
| `listAsync()` | Non-blocking `CompletableFuture` twin of `list()`. |

### Plan

Caps and usage.

| Method | Description |
|--------|-------------|
| `get()` | Plan, caps, per-feature usage and the upgrade offer. |

### Settings

Compliance settings.

| Method | Description |
|--------|-------------|
| `getSenderAddress()` | The CAN-SPAM postal address on file. |
| `setSenderAddress()` | Set the CAN-SPAM postal address — sends are blocked until this exists. |

### Ads

Paid-audience export.

| Method | Description |
|--------|-------------|
| `linkedinCompanyAudience()` | Build a LinkedIn company audience from your leads. |

### Lead finder (path-parameter helpers)

`client.leadFinder` holds URL-encoding twins of the `client.leads` methods that
take an id. The `leads` versions splice the id into the path **raw**, so prefer
these whenever the value is not already a bare slug — a domain, an email or
anything that might carry a `/`, a space or a `#`. The same split explains the
`remove()` and `setStatus()` aliases elsewhere on this page: same endpoint, id
encoded.

| Method | Description |
|--------|-------------|
| `company()` | Company profile for a domain. |
| `companyPeople()` | People found at that company. |
| `job()` | Poll a search job for status and the results so far. |
| `jobFeedback()` | Rate a job's results so scoring improves. |
| `syncList()` | Sync a lead list to its connected destination. |
| `removeSavedSearch()` | Delete a saved search. |
| `updateScoringRule()` | Update a lead-scoring rule. |
| `removeScoringRule()` | Delete a lead-scoring rule. |

---

## Usage

### Find leads

`leads.search()` returns a job id, not leads — the search runs asynchronously.

```java
Map<String, Object> started = client.leads.search(Map.of(
        "query", "heads of ops at logistics startups",
        "useAI", true,
        "filters", Map.of("location", "Berlin", "companySize", "11-50")));
String jobId = (String) started.get("jobId");
```

### Stream job progress

`leads.stream()` blocks the calling thread until the server closes the stream,
handing each frame to your `Consumer`.

```java
client.leads.stream(jobId, event -> {
    switch (event.event()) {
        case "progress" -> System.out.println("working " + event.data());
        case "found" -> System.out.println("hit " + event.data());
        case "complete" -> System.out.println("done " + event.data());
        case "error", "timeout" -> System.err.println(event.event() + " " + event.data());
        default -> System.out.println(event.event() + " " + event.raw());
    }
});
```

There is no cancellation handle — no `AbortSignal` equivalent, and interrupting
the thread will not break the blocking socket read. Run it on a thread you are
willing to leave parked, and rely on the server's own 15-minute stream ceiling
(which arrives as a `timeout` event) to end it. Streams are never retried:
replaying one that failed mid-flight would duplicate whatever you already
consumed.

A job that finished before you subscribed still works — the server answers with
a JSON snapshot instead of a stream, and you get exactly one `complete` (or
`error`) frame rather than silence:

```java
client.leads.stream(finishedJobId, event ->
        System.out.println("finished job arrives as: " + event.event()));
```

### Poll instead of streaming

```java
Map<String, Object> snapshot = client.leads.job(jobId);
Map<?, ?> job = (Map<?, ?>) snapshot.get("job");
System.out.println(job.get("status") + " / " + job.get("total_found"));
```

`results` is empty unless `job.status` is `running` or `done` — a pay-to-view
rule, not a pagination artefact.

### List saved leads

```java
Map<String, Object> page = client.leads.leads(Map.of("page", 1, "limit", 50));
System.out.println(page.get("total") + " saved leads");
```

Pass `Map.of()` — or `null` — when you want no query parameters.

### Create a CRM contact and a deal

```java
client.contacts.create(Map.of(
        "email", "cto@acme.com",
        "firstName", "Dana",
        "status", "subscribed",
        "consent", Map.of(
                "source", "signup form /pricing",
                "timestamp", Instant.now().toString())));

Map<String, Object> created = client.deals.create(Map.of(
        "leadEmail", "cto@acme.com",   // the only required field
        "leadName", "Dana Reyes",
        "value", 12000,
        "currency", "USD"));
String dealId = (String) ((Map<?, ?>) created.get("deal")).get("id");
```

`Map.of()` rejects null values and caps at 10 pairs — use `Map.ofEntries()` or a
`HashMap` for a wider or nullable body.

### Read and move the pipeline

```java
Map<String, Object> board = client.pipeline.get(Map.of());
System.out.println(board.get("stages"));

client.pipeline.create(Map.of("dealId", dealId, "newStage", "meeting"));
```

`newStage` must be one of `new`, `contacted`, `interested`, `meeting`,
`proposal`, `closed`, `lost`.

### Run a campaign

```java
Map<String, Object> campaign = client.campaigns.create(Map.of(
        "name", "Q3 fintech outbound",
        "steps", List.of(
                Map.of("channel", "email",
                       "subject", "Quick question",
                       "body", "Hi {{name}} …"),
                Map.of("channel", "email",
                       "delay_hours", 72,
                       "body", "Following up …"))));
String campaignId = (String) campaign.get("id");

Map<String, Object> result = client.campaigns.enqueue(campaignId, Map.of(
        "recipients", List.of(Map.of(
                "email", "cto@acme.com", "name", "Dana Reyes", "company", "Acme"))));

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
System.out.println(result.get("queued") + " queued, "
        + result.get("skipped") + " skipped, warnings: " + result.get("warnings"));
```

Step order is the array index — there is no `step_order` field to set, and
`subject`/`body` sit directly on the step rather than in a nested template.
`create` answers `{ ok, id }`, not the whole campaign.

### Check the plan before an expensive run

```java
Map<String, Object> plan = client.plan.get();
Map<?, ?> searches = (Map<?, ?>) ((Map<?, ?>) plan.get("usage")).get("lead_searches");
Object remaining = searches.get("remaining");

if (remaining == null) {
    System.out.println("unlimited lead searches on "
            + ((Map<?, ?>) plan.get("plan")).get("name"));
} else if (((Number) remaining).intValue() == 0) {
    Map<?, ?> upgrade = (Map<?, ?>) plan.get("upgrade");
    System.out.println("no searches left; upgrade at "
            + (upgrade == null ? "(none offered)" : upgrade.get("url")));
}
```

`usage` is keyed by `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals` and `linkedin_seats`. Plan slugs are `free`, `starter`, `pro`
and `scale`.

### Reply into a conversation

```java
Map<String, Object> inbox = client.conversations.list(Map.of("limit", 25));
System.out.println(((List<?>) inbox.get("conversations")).size() + " threads");

client.conversations.reply("cto@acme.com", Map.of(
        "message", "Happy to walk you through it — does Thursday work?"));
```

The field is `message` (1–5000 characters), optionally with `conversationId` to
pick a thread; the channel is decided by the thread, not by you. The email in
the path is URL-encoded for you.

### Async variants

```java
CompletableFuture<Map<String, Object>> future =
        client.leads.searchAsync(Map.of("query", "fintech CFOs"));
try {
    System.out.println("async jobId " + future.join().get("jobId"));
} catch (CompletionException e) {
    if (e.getCause() instanceof MisarReachException reach) {
        System.err.println("async call failed: " + reach.getStatus());
    }
}
```

The async twins run the same blocking call on `ForkJoinPool.commonPool()` and
wrap any failure in a `CompletionException` — unwrap with `getCause()` to get
back to `MisarReachException` or `UpgradeRequiredException`. If you need a
different executor, pass one to `CompletableFuture.supplyAsync` around the
synchronous method instead.

---

## Errors

This SDK has a deliberately thin hierarchy — **two exception types, not five.**
There is no `AuthException`, `NotFoundException` or `RateLimitError` here as
there is in the TypeScript and Python SDKs: 401, 403, 404 and plain 429 all
arrive as `MisarReachException`, and you tell them apart with `getStatus()`.

| Class | Thrown for | Carries |
|-------|-----------|---------|
| `MisarReachException` | every non-2xx that is not a plan refusal — 400, 401, 403, 404, plain 429, 5xx after retries — plus network failure, request-serialisation failure and an unparseable response body | `getStatus()`; `0` for anything that never reached an HTTP status |
| `UpgradeRequiredException` *(extends `MisarReachException`)* | a plan cap was hit — see below | `getFeature()`, `getLimit()`, `getCurrent()`, `getUpgradeUrl()`, plus `getStatus()` |

Both are **checked** exceptions, so every synchronous method declares
`throws MisarReachException`. `getMessage()` is prefixed with the status —
`MisarReachException(401): Invalid API key` — and the trailing text is the
server's own message, lifted from the `{ "error": { "message": … } }` envelope.

```java
try {
    client.leads.search(Map.of("query", "…"));
} catch (UpgradeRequiredException err) {          // must precede the base class
    System.err.println(err.getFeature() + ": " + err.getCurrent() + "/" + err.getLimit());
    System.err.println("upgrade at " + err.getUpgradeUrl());
} catch (MisarReachException err) {
    switch (err.getStatus()) {
        case 401, 403 -> System.err.println("missing, invalid or out-of-scope mrk_ key");
        case 404 -> System.err.println("no such record");
        case 429 -> System.err.println("rate limited — the SDK already retried");
        case 0 -> System.err.println("network failure, or retries exhausted");
        default -> System.err.println("api error " + err.getStatus() + ": " + err.getMessage());
    }
}
```

`UpgradeRequiredException` is a subclass, so its `catch` block must come first;
put `MisarReachException` above it and javac will reject the file.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces on the first attempt. `getUpgradeUrl()` is
resolved to an absolute URL: the server sends `/settings?tab=billing` and you
get `https://misarreach.com/settings?tab=billing`.

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments — the retry loop reads the body, so an allowance refusal is
never mistaken for rate limiting and burned through the back-off. This is
distinct from the 503 `retry: true` the server sends when it could not *check*
the quota: that one carries no `upgrade` flag and **is** retried, so "we don't
know" is never mistaken for "you're over your limit".

The same mapping applies to `leads.stream()`, so a plan refusal on the stream
raises `UpgradeRequiredException` before the first frame rather than a bare
`IOException`.

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Because the payload is an untyped map,
`remaining` is a `null` value, so check `== null` *before* casting to `Number`;
unboxing it straight into an `int` throws `NullPointerException` on exactly the
plans that have no ceiling.

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.setSenderAddress()`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **Maven Central** — https://central.sonatype.com/artifact/io.misar/misarreach-java

MIT © [Misar AI](https://misar.io)
