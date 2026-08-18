# MisarReach Kotlin SDK

> Kotlin coroutine client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![JVM 17+](https://img.shields.io/badge/JVM-17%2B-orange.svg)](https://adoptium.net/)
[![Maven Central](https://img.shields.io/badge/Maven%20Central-io.misar%3Amisarreach--kotlin-blue.svg)](https://central.sonatype.com/artifact/io.misar/misarreach-kotlin)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**17 resource groups · 94 operations**

Requires JVM 17+. Every method is a `suspend fun` over `Map<String, Any>`, and
lead-search progress arrives as a `Flow`. HTTP comes from the JDK's own client.
Talks to `https://api.misar.io/reach/api`.

---

## Install

Gradle (Kotlin DSL):

```kotlin
dependencies {
    implementation("io.misar:misarreach-kotlin:1.0.0")
    // Declare coroutines yourself — see the note below.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
}
```

Gradle (Groovy DSL):

```groovy
dependencies {
    implementation 'io.misar:misarreach-kotlin:1.0.0'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0'
}
```

Maven:

```xml
<dependencies>
  <dependency>
    <groupId>io.misar</groupId>
    <artifactId>misarreach-kotlin</artifactId>
    <version>1.0.0</version>
  </dependency>
  <dependency>
    <groupId>org.jetbrains.kotlinx</groupId>
    <artifactId>kotlinx-coroutines-core</artifactId>
    <version>1.8.0</version>
  </dependency>
</dependencies>
```

Requires JVM 17+.

**Declare `kotlinx-coroutines-core` yourself.** The 1.0.0 POM lists it at
`runtime` scope, so it reaches your runtime classpath but *not* your compile
classpath — and this SDK's public API is made of coroutine types
(`leads.stream()` returns a `Flow`, and every other method is a `suspend fun`
you need a coroutine builder to call). Depending on `misarreach-kotlin` alone
fails at compile time with `Unresolved reference: kotlinx`. Adding the line
above is the whole fix; the version must match 1.8.0 or newer.

`jackson-module-kotlin` 2.17.1 arrives transitively and needs no declaration —
no Jackson type appears in the public API. The HTTP client is the JDK's own, so
there is no third-party transport to align.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```kotlin
import io.misar.reach.MisarReachClient

val reach = MisarReachClient(System.getenv("MISARREACH_API_KEY"))
```

The API key is the only required constructor argument; `baseUrl` and
`maxRetries` follow it.

---

## Quick start

```kotlin
import io.misar.reach.MisarReachClient
import kotlinx.coroutines.runBlocking

@Suppress("UNCHECKED_CAST")
fun main() = runBlocking {
    val reach = MisarReachClient(System.getenv("MISARREACH_API_KEY"))

    val job = reach.leads.search(mapOf("query" to "CTOs at Series A fintech", "useAI" to true))
    val jobId = job["jobId"] as String

    val snapshot = reach.leads.job(jobId)
    val meta = snapshot["job"] as Map<String, Any>
    val results = snapshot["results"] as List<Any>
    println("${meta["status"]} — ${results.size} results")
}
```
---

## What's in the package

- `MisarReachClient(apiKey, baseUrl = "https://api.misar.io/reach/api", maxRetries = 3, httpClient = null)`
  — resources are plain `val` accessors on the instance: `reach.leads`,
  `reach.deals`, `reach.pipeline`, `reach.channels`, `reach.autopilot`,
  `reach.salesAgent`, `reach.campaigns`, `reach.contacts`, `reach.conversations`,
  `reach.workspaces`, `reach.settings`, `reach.plan`, `reach.ads`,
  `reach.campaignTemplates`, `reach.deliverability`, `reach.notifications`,
  `reach.webhooks`.
- **No typed models.** Unlike the TypeScript and Python SDKs, every method here
  takes and returns `Map<String, Any>` — the JSON decoded by Jackson, verbatim.
  Nothing is reshaped, so the API reference is the field reference; expect to
  cast (`job["jobId"] as String`) and to `@Suppress("UNCHECKED_CAST")` when you
  reach into a nested object. The only data class in the package is
  `ReachSseEvent(event, data, raw)`.
- **93 of the 94 methods are `suspend fun`.** The exception is
  `leads.stream(jobId)`, which is a plain `fun` returning `Flow<ReachSseEvent>`.
- **Errors** — three types only: `MisarReachException`, and its subclasses
  `MisarReachNetworkException` and `UpgradeRequiredException`. There is no
  per-status subclass; see [Errors](#errors).
- **Transport** — the JDK's `java.net.http.HttpClient`, `Bearer` auth, a 10s
  connect and 30s request timeout. It retries with exponential back-off from
  500 ms on 429/500/502/503/504. A 402 plan refusal is never retried, nor is a
  429 carrying `upgrade: true`, which the loop inspects the body to tell apart
  from genuine rate limiting. Pass your own `HttpClient` as the fourth argument
  to control proxies, TLS or redirects.
- **SSE streaming** for lead-finder job progress, as a `Flow` that is already
  `flowOn(Dispatchers.IO)`. The server sends *named* events — `progress`,
  `found`, `complete`, `error`, `timeout` — plus a `: keepalive` comment every 20
  seconds. There is no `[DONE]` sentinel; the flow simply completes when the
  server closes the stream. A job that has **already finished** is answered with
  a JSON snapshot rather than a stream, and the SDK emits the terminal
  `complete`/`error` frame in its place, so a caller that assumed a stream does
  not hang on nothing.

### Two behaviours worth knowing before you wire this in

**`suspend` does not mean non-blocking here.** `HttpClient.send` is synchronous
and the retry back-off is a `Thread.sleep`, so every `suspend` method occupies
its calling thread for the whole request. On a confined dispatcher that starves
everything else scheduled on it — measured on a single-threaded dispatcher, a
call that retried for 1.6 s blocked a second coroutine for the full 1.6 s, and
wrapping the same call in `withContext(Dispatchers.IO)` let it through in 56 ms.
Call from `Dispatchers.IO`, or wrap:

```kotlin
val plan = withContext(Dispatchers.IO) { reach.plan.get() }
```

`leads.stream()` needs no wrapper — its flow already carries `flowOn(Dispatchers.IO)`.

**`maxRetries` counts attempts, not retries.** The default of `3` means one call
plus two retries. `maxRetries = 1` disables retrying. `maxRetries = 0` does *not*
mean "never retry" — it makes **no HTTP request at all** and throws
`MisarReachNetworkException("max retries exceeded")`.

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

### Pipeline

The Kanban board and stage moves.

| Method | Description |
|--------|-------------|
| `get()` | Kanban board of deals grouped by stage, with revenue totals. |
| `create()` | Move a deal to another stage. |

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

### Campaign templates

Reusable starting points.

| Method | Description |
|--------|-------------|
| `list()` | Built-in templates plus your saved ones. |
| `create()` | Save a template from steps or by copying a campaign. |

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

### Conversations

The unified inbox.

| Method | Description |
|--------|-------------|
| `list()` | Unified inbox — one row per contact, across every channel. |
| `get()` | One contact's full timeline. |
| `reply()` | Send a human reply into a thread. |

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

### Autopilot

Goal-driven runs.

| Method | Description |
|--------|-------------|
| `start()` | Start an autopilot run from a stated goal. |
| `runs()` | List autopilot runs, with the caller's plan limits. |
| `get()` | Read one autopilot run. |
| `status()` | Poll a run's status. |
| `updateStatus()` | Pause, resume or stop a run. |

### Deliverability

Sender reputation.

| Method | Description |
|--------|-------------|
| `get()` | Sender health: bounce and complaint rates against *attempted* sends, plus a verdict. |

### Notifications

The in-app bell.

| Method | Description |
|--------|-------------|
| `list()` | In-app notifications, newest first, with the unread count. |
| `markRead()` | Mark notifications read — `{ids: [...]}` or `{all: true}`. |

### Webhooks

Signed outbound endpoints.

| Method | Description |
|--------|-------------|
| `list()` | Registered endpoints and their delivery health. |
| `create()` | Register an endpoint; the signing secret is returned once only. |

### Workspaces

Teams and membership.

| Method | Description |
|--------|-------------|
| `list()` | Workspaces you belong to. |
| `create()` | Create a workspace. |
| `members()` | List members. |
| `addMember()` | Invite a member. |
| `removeMember()` | Remove a member. |

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

---

## Usage

### Find leads

`leads.search()` returns a job id, not leads — the search runs asynchronously.

```kotlin
val job = reach.leads.search(
    mapOf(
        "query" to "heads of ops at logistics startups",
        "useAI" to true,
        "filters" to mapOf("location" to "Berlin", "companySize" to "11-50"),
    )
)
val jobId = job["jobId"] as String
```

### Stream job progress

```kotlin
reach.leads.stream(jobId).collect { ev ->
    when (ev.event) {
        "progress" -> println("working: ${ev.data?.get("message")}")
        "found" -> println("hit: ${ev.data?.get("total")}")
        "complete" -> println("done: ${ev.data?.get("total_found")} found")
        "error", "timeout" -> System.err.println("${ev.event}: ${ev.data}")
        else -> println("${ev.event}: ${ev.raw}")
    }
}
```

The flow ends when the server closes the stream. Nothing else stops it, so bound
a stuck job yourself — `withTimeoutOrNull(10.minutes) { … }`, or cancel the
enclosing scope. `ev.data` is `null` when a frame was not JSON; `ev.raw` always
holds what arrived. A stream is never retried: replaying one that failed
mid-flight would duplicate whatever you had already consumed.

### List saved leads

```kotlin
val page = reach.leads.leads(mapOf("limit" to 50))
println(page["total"])
```

Query parameters are stringified with `toString()` and URL-encoded, so pass
scalars — a `List` value would be encoded as its Kotlin `toString()`, not as
repeated parameters.

### Create a CRM contact and a deal

```kotlin
reach.contacts.create(
    mapOf(
        "email" to "cto@acme.com",
        "firstName" to "Dana",
        "status" to "subscribed",
        "consent" to mapOf(
            "source" to "signup form /pricing",
            "timestamp" to java.time.Instant.now().toString(),
        ),
    )
)

val created = reach.deals.create(
    mapOf(
        "leadEmail" to "cto@acme.com",
        "leadName" to "Dana Reyes",
        "value" to 12000,
        "currency" to "USD",
    )
)
@Suppress("UNCHECKED_CAST")
val dealId = (created["deal"] as Map<String, Any>)["id"] as String
```

`leadEmail` is the only required field on a deal.

### Read and move the pipeline

```kotlin
val board = reach.pipeline.get()
@Suppress("UNCHECKED_CAST")
val byStage = board["board"] as Map<String, List<Any>>
println("${(board["stages"] as List<*>).size} stages, ${byStage["new"]?.size ?: 0} in `new`")

// POST /pipeline moves a deal between stages; `create` is the method name, not
// the effect. It takes `dealId` and `newStage`, and 400s on an unknown stage.
reach.pipeline.create(mapOf("dealId" to dealId, "newStage" to "meeting"))
```

### Run a campaign

```kotlin
val campaign = reach.campaigns.create(
    mapOf(
        "name" to "Q3 fintech outbound",
        "steps" to listOf(
            mapOf("channel" to "email", "subject" to "Quick question", "body" to "Hi {{name}} …"),
            mapOf("channel" to "email", "delay_hours" to 72, "body" to "Following up …"),
        ),
    )
)
val campaignId = campaign["id"] as String

val result = reach.campaigns.enqueue(
    campaignId,
    mapOf(
        "recipients" to listOf(
            mapOf("email" to "cto@acme.com", "name" to "Dana Reyes", "company" to "Acme")
        )
    ),
)

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
println("${result["queued"]} ${result["skipped"]} ${result["warnings"]}")
```

Steps carry `channel`, `subject`, `body` and `delay_hours` — the array index
becomes `step_order`, so order the list rather than numbering it. A recipient
needs at least one address the step's channel can use: `email`, `linkedinUrl`,
`phone` (SMS/WhatsApp) or `handle` (Instagram, Facebook, X, Telegram, Discord).

### Check the plan before an expensive run

```kotlin
val plan = reach.plan.get()
@Suppress("UNCHECKED_CAST")
val usage = plan["usage"] as Map<String, Map<String, Any?>>
val searches = usage.getValue("lead_searches")

when (val remaining = searches["remaining"]) {
    null -> println("unlimited lead searches on ${(plan["plan"] as Map<*, *>)["name"]}")
    0 -> println("none left; upgrade at ${(plan["upgrade"] as Map<*, *>?)?.get("url")}")
    else -> println("$remaining of ${searches["limit"]} lead searches left")
}
```

`usage` is keyed by counter: `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals`, `linkedin_seats`. `upgrade` is null until at least one cap has
been spent, so its presence is the signal to show an upgrade path.

### Reply into a conversation

```kotlin
val inbox = reach.conversations.list(mapOf("limit" to 25))

val sent = reach.conversations.reply(
    "cto@acme.com",
    mapOf("message" to "Happy to walk you through it — does Thursday work?"),
)
println("sent over ${sent["channel"]} as ${sent["messageId"]}")
```

The field is `message`, not `body`, and you do not pick the channel — the
thread's own channel decides the transport, and the response tells you which one
was used. Add `conversationId` to target a thread other than the most recent.

---

## Errors

Every non-2xx throws. There are three exception classes, and only three — no
`AuthException`, no `NotFoundException`. 401, 403, 404, 422 and plain 429s all
arrive as `MisarReachException`, so branch on `status`.

| Class | Thrown for |
|-------|-----------|
| `UpgradeRequiredException` | a counted plan cap — 402, or 429 carrying `upgrade: true`. Adds `feature`, `limit`, `current`, `upgradeUrl` |
| `MisarReachNetworkException` | transport failure (DNS, connection refused, timeout) or retries exhausted. `status` is `0` |
| `MisarReachException` | every other non-2xx — 401, 403, 404, 422, rate-limit 429, 5xx. Carries `status` |

Both subclasses extend `MisarReachException`, so order your `catch` blocks
narrowest first. `message` is prefixed by the class and status —
`MisarReachException(401): Invalid API key` — with the tail extracted from the
server's `{"error": {"message": …}}` envelope.

```kotlin
import io.misar.reach.MisarReachException
import io.misar.reach.MisarReachNetworkException
import io.misar.reach.UpgradeRequiredException

try {
    reach.leads.search(mapOf("query" to "…"))
} catch (err: UpgradeRequiredException) {
    // e.g. feature "lead_searches", current 50 of limit 50
    println("plan cap ${err.feature}: ${err.current}/${err.limit}")
    println("upgrade at ${err.upgradeUrl}")   // resolved to an absolute URL
} catch (err: MisarReachNetworkException) {
    println("transport failed or retries exhausted: ${err.message}")
} catch (err: MisarReachException) {
    when (err.status) {
        401, 403 -> println("key rejected or out of scope: ${err.message}")
        404 -> println("not found: ${err.message}")
        else -> println(err.message)
    }
}
```

The same mapping applies to the SSE stream, so a plan refusal on
`leads.stream()` arrives as the same typed exception, not a bare `Exception`.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces immediately. 429 is still accepted as an upgrade
refusal when `upgrade: true` is present, for older deployments. The server sends
`upgrade_url` app-relative; the SDK resolves it against
`https://misarreach.com` before putting it on `err.upgradeUrl`.

This is distinct from the **503 with `retry: true`** the server sends when it
could not *check* the quota — that one carries no `upgrade` flag and is retried
normally, so "we don't know" is never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Because everything is `Map<String, Any>`,
that arrives as a Kotlin `null`, and `0` arrives as a boxed `Int`. Match on
`null` before comparing:

```kotlin
val remaining = searches["remaining"]           // null = unlimited, 0 = exhausted
if (remaining != null && remaining == 0) error("cap reached")
```

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
- **Maven Central** — https://central.sonatype.com/artifact/io.misar/misarreach-kotlin

MIT © [Misar AI](https://misar.io)
