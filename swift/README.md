# MisarReach Swift SDK

> Swift concurrency client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://github.com/Misar-AI/misarreach-swift)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgrey.svg)](https://github.com/Misar-AI/misarreach-swift)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**17 resource groups · 94 operations**

Built with swift-tools-version 5.9 for macOS 12+, iOS 15+, tvOS 15+, watchOS 8+
and Linux through swift-corelibs-foundation. Every method is `async throws` and
returns `[String: Any]`, matching the open-shape API contract. Talks to
`https://api.misar.io/reach/api`.

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Misar-AI/misarreach-swift.git", from: "5.0.2"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "MisarReach", package: "misarreach-swift")]
    ),
]
```

Built with swift-tools-version 5.9. Platforms: macOS 12+, iOS 15+, tvOS 15+,
watchOS 8+, and Linux through swift-corelibs-foundation.

> SwiftPM requires `Package.swift` at a repository root, so the package is
> mirrored to its own repository — a URL pointing into the monorepo will not
> resolve. Note also that the package name in `.product(name:package:)` is
> `misarreach-swift`, taken from the repository, while the module you `import`
> is `MisarReach`.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```swift
import MisarReach

let reach = MisarReachClient(
    apiKey: ProcessInfo.processInfo.environment["MISARREACH_API_KEY"] ?? ""
)
```

`apiKey:` is the only required argument; `baseURL:`, `maxRetries:` and
`session:` are optional.

---

## Quick start

```swift
import MisarReach

let reach = MisarReachClient(
    apiKey: ProcessInfo.processInfo.environment["MISARREACH_API_KEY"] ?? ""
)

let job = try await reach.leads.search([
    "query": "CTOs at Series A fintech",
    "useAI": true,
])
guard let jobId = job["jobId"] as? String else { return }

let snapshot = try await reach.leads.jobStatus(jobId: jobId)
let status = (snapshot["job"] as? [String: Any])?["status"] as? String ?? "unknown"
let results = snapshot["results"] as? [[String: Any]] ?? []
print(status, results.count)
```

---

## What's in the package

- `MisarReachClient` — a `final class`, not an actor, built with
  `MisarReachClient(apiKey:baseURL:maxRetries:session:)`. Only `apiKey` is
  required; `baseURL` defaults to the production API (a trailing slash is
  trimmed for you), `maxRetries` to 3 and `session` to `URLSession.shared`.
- **17 resource classes**, reached as computed properties on the client —
  `reach.leads`, `reach.ads`, `reach.autopilot`, `reach.campaigns`,
  `reach.campaignTemplates`, `reach.channels`, `reach.contacts`,
  `reach.conversations`, `reach.deals`, `reach.deliverability`,
  `reach.notifications`, `reach.pipeline`, `reach.plan`, `reach.salesAgent`,
  `reach.settings`, `reach.webhooks`, `reach.workspaces`. Between them they
  expose 94 methods, one for every operation in `openapi/reach.openapi.json`.
  Their initialisers are internal: go through the client rather than
  constructing a resource yourself.
- **No generated models.** Every call is `async throws` and returns
  `[String: Any]` straight from `JSONSerialization`; request bodies are
  `[String: Any]` too. Read values with conditional casts — and note that a JSON
  `null` arrives as `NSNull`, never as `nil`.
- **Query parameters are a raw query string**, not a dictionary:
  `leads.list(params: "page=1&limit=50")`. Percent-encode your own values. Path
  segments *are* encoded for you, so an email address in a URL is safe.
- **Errors** — a single enum, `MisarReachError`, with the four cases below.
- **Transport** — `URLSession`, a `Bearer` header and a 30-second request
  timeout, retrying up to `maxRetries` attempts (default 3, so two retries) with
  exponential back-off — 0.5s, then 1s — on 429, 500, 502, 503 and 504. A 402
  plan refusal is never retried. On Linux the async `URLSession.data(for:)` is
  bridged from the completion-handler API, so there is one implementation on
  every platform rather than two behind `#if`.
- **SSE streaming** for lead-finder job progress, delivered as a **callback**
  rather than an `AsyncSequence`: `streamJob(jobId:onEvent:)` is itself
  `async throws` and returns once the server closes the stream. The server sends
  *named* events — `progress`, `found`, `complete`, `error`, `timeout` — as
  `MisarReachStreamEvent` values (`.event`, `.data`, `.raw`), plus a
  `: keepalive` comment every 20 seconds. There is no `[DONE]` sentinel. A job
  that has **already finished** is answered with a JSON snapshot rather than a
  stream, and the SDK synthesises the terminal `complete` — or `error` when the
  job failed — so a caller that assumed a stream does not hang on nothing.
  Streams are never retried: replaying one that failed mid-flight would
  duplicate whatever the caller had already consumed.

---

## Resources

Every public method, grouped the way the client groups them.

### Lead finder

23-source search, enrichment, verification, scoring, lists and the SSE job stream.

| Method | Description |
|--------|-------------|
| `account()` | Lead-finder credit balance and provider account state. |
| `config()` | Which sources, filters and AI options this workspace may use. |
| `list()` | Saved leads, paginated, newest first. |
| `export()` | Export saved leads as CSV or JSON. |
| `search()` | Start an async search across 23 sources — returns a `jobId`, not leads. |
| `discoverCompanies()` | Company and lead discovery by firmographic filters. |
| `enrich()` | Enrich a saved lead from external data (spends credits). |
| `verifyEmails()` | Verify email deliverability for one address or a batch (spends credits). |
| `score()` | AI-score leads by job id or an explicit lead-id list. |
| `jobStatus()` | Poll a search job for status and the results so far. |
| `submitFeedback()` | Rate a job's results so scoring improves. |
| `streamJob()` | SSE progress for a running job — named events, no `[DONE]` sentinel. |
| `listLeadLists()` | Lead lists in the workspace. |
| `createLeadList()` | Create a lead list. |
| `syncLeadList()` | Sync a lead list to its connected destination. |
| `savedSearches()` | Saved search definitions. |
| `createSavedSearch()` | Save a search for reuse. |
| `deleteSavedSearch()` | Delete a saved search. |
| `scoringRules()` | Lead-scoring rules for this workspace. |
| `createScoringRule()` | Create a lead-scoring rule. |
| `updateScoringRule()` | Update a lead-scoring rule. |
| `deleteScoringRule()` | Delete a lead-scoring rule. |
| `recommendations()` | Suggested next leads based on what you have already saved. |
| `searchHistory()` | Past searches with their result counts. |
| `previewMessage()` | Draft the AI outreach message for a lead without sending it. |
| `sendToCampaign()` | Push selected leads into an existing campaign. |
| `addToSegment()` | Add selected leads to a contact segment. |
| `company()` | Company profile for a domain. |
| `companyPeople()` | People found at that company. |

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
| `actions()` | What the agent did today. |
| `config()` | Agent config — offer, booking link, daily reply cap, confidence threshold. |
| `updateConfig()` | Update the agent config. |
| `conversations()` | Conversations the agent is handling. |
| `process()` | Run the agent over one conversation. |

### Autopilot

Goal-driven runs.

| Method | Description |
|--------|-------------|
| `runs()` | List autopilot runs, with the caller's plan limits. |
| `start()` | Start an autopilot run from a stated goal. |
| `get()` | Read one autopilot run. |
| `status()` | Poll a run's status. |
| `setStatus()` | Pause, resume or stop a run. |

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
| `listMembers()` | List members. |
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
| `senderAddress()` | The CAN-SPAM postal address on file. |
| `setSenderAddress()` | Set the CAN-SPAM postal address — sends are blocked until this exists. |

### Ads

Paid-audience export.

| Method | Description |
|--------|-------------|
| `linkedinCompanyAudience()` | Build a LinkedIn company audience from your leads. |

---

## Usage

### Find leads

`leads.search(_:)` returns a job id, not leads — the search runs asynchronously.

```swift
let job = try await reach.leads.search([
    "query": "heads of ops at logistics startups",
    "useAI": true,
    "filters": ["location": "Berlin", "companySize": "11-50"],
])
let jobId = job["jobId"] as? String ?? ""
```

### Stream job progress

```swift
try await reach.leads.streamJob(jobId: jobId) { event in
    switch event.event {
    case "progress":
        print("working", event.data["message"] ?? "", event.data["total_found"] ?? 0)
    case "found":
        print("hit", event.data["email"] ?? "")
    case "complete":
        print("done", event.data["total_found"] ?? 0)
    case "error", "timeout":
        print("failed", event.data["error"] ?? "")
    default:
        break
    }
}
```

The call suspends until the stream ends, so wrap it in a `Task` you can cancel
if a stuck job must not hold the connection. The same `complete` / `error` cases
fire when the job had already finished before you subscribed — that answer is a
JSON snapshot, which the SDK turns into the terminal event for you.

### List saved leads

```swift
let page = try await reach.leads.list(params: "page=1&limit=50")
print(page["total"] ?? 0)
```

### Create a CRM contact and a deal

```swift
_ = try await reach.contacts.create([
    "email": "cto@acme.com",
    "firstName": "Dana",
    "status": "subscribed",
    "consent": [
        "source": "signup form /pricing",
        "timestamp": ISO8601DateFormatter().string(from: Date()),
    ],
])

let created = try await reach.deals.create([
    "leadEmail": "cto@acme.com",
    "leadName": "Dana Reyes",
    "value": 12_000,
    "currency": "USD",
])
let dealId = (created["deal"] as? [String: Any])?["id"] as? String ?? ""
```

### Read and move the pipeline

```swift
let board = try await reach.pipeline.get()
print(board["stages"] as? [String] ?? [])

// The stage move is POST /pipeline — it lives on `pipeline`, not on `deals`.
let moved = try await reach.pipeline.create(["dealId": dealId, "newStage": "meeting"])
print((moved["deal"] as? [String: Any])?["stage"] ?? "")
```

### Run a campaign

Steps are flat — `channel`, `delay_hours`, `subject`, `body` — and their order
in the array becomes `step_order`.

```swift
let campaign = try await reach.campaigns.create([
    "name": "Q3 fintech outbound",
    "steps": [
        ["channel": "email", "subject": "Quick question", "body": "Hi {{name}} …"],
        ["channel": "email", "delay_hours": 72, "body": "Following up …"],
    ],
])
let campaignId = campaign["id"] as? String ?? ""

let result = try await reach.campaigns.enqueue(id: campaignId, data: [
    "recipients": [["email": "cto@acme.com", "name": "Dana Reyes", "company": "Acme"]],
])

// Check `warnings`: a step whose channel has no inbound path in this
// deployment can never deliver, and the server reports that here rather
// than silently dropping every recipient at dispatch time.
print(result["queued"] ?? 0, result["skipped"] ?? 0, result["warnings"] ?? [])
```

### Check the plan before an expensive run

```swift
let plan = try await reach.plan.get()
let usage = plan["usage"] as? [String: Any] ?? [:]
let searches = usage["lead_searches"] as? [String: Any] ?? [:]

// JSONSerialization decodes a JSON null to NSNull, never to nil, so an
// unlimited counter has to be tested for before it is compared.
if searches["remaining"] is NSNull {
    let name = (plan["plan"] as? [String: Any])?["name"] as? String ?? ""
    print("unlimited lead searches on", name)
} else if let remaining = searches["remaining"] as? Int, remaining == 0 {
    let url = (plan["upgrade"] as? [String: Any])?["url"] as? String ?? ""
    print("no searches left; upgrade at", url)
}
```

`usage` is keyed by `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals` and `linkedin_seats`.

### Reply into a conversation

The field is `message`, and the thread's own channel decides the transport — you
do not choose it.

```swift
let inbox = try await reach.conversations.list(params: "limit=25")
print(inbox["total"] ?? 0)

_ = try await reach.conversations.reply(email: "cto@acme.com", data: [
    "message": "Happy to walk you through it — does Thursday work?",
])
```

---

## Errors

Every non-2xx throws a `MisarReachError`. It is an enum, so handle it with a
`switch` rather than an `is` ladder; `error.status` gives the HTTP status (0 for
a transport failure) and the type prints itself usefully in a log.

| Case | Thrown for |
|------|-----------|
| `.upgradeRequired(status:message:feature:limit:current:upgradeURL:)` | a plan cap was hit — see below |
| `.rateLimit(message:balance:freeRemaining:upgrade:)` | 429 rate limiting; carries wallet `balance` and `freeRemaining` |
| `.apiError(status:message:code:)` | any other non-2xx — **including 401, 403 and 404** |
| `.networkError(message:)` | transport failure, or every retry exhausted |

Unlike the TypeScript and Python SDKs there is no separate auth or not-found
type: a bad `mrk_` key arrives as `.apiError(status: 401, …)`, so branch on
`status`.

The same mapping applies to the SSE stream, so a plan refusal on
`leads.streamJob(jobId:onEvent:)` arrives as the same typed error, not a bare
`URLError`.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so 402 is left
out of the retry set and surfaces immediately:

```swift
do {
    _ = try await reach.leads.search(["query": "CTOs at Series A fintech"])
} catch let error as MisarReachError {
    switch error {
    case let .upgradeRequired(_, message, feature, limit, current, upgradeURL):
        // e.g. feature "lead_searches", current 50 of limit 50
        print(feature ?? "-", "\(current ?? 0)/\(limit ?? 0)", message)
        print("upgrade at", upgradeURL ?? "")   // resolved to an absolute URL
    case let .rateLimit(message, balance, freeRemaining, _):
        print("rate limited", message, balance ?? 0, freeRemaining ?? 0)
    case let .apiError(status, message, code):
        print("api error", status, code ?? "-", message)
    case let .networkError(message):
        print("transport", message)
    }
}
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments — it too arrives as `.upgradeRequired`, though because 429 is
in the retry set the client spends its back-off before surfacing it. This is
distinct from the 503 `retry: true` the server sends when it could not *check*
the quota: that one is retried and usually succeeds, so "we don't know" is never
mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is null when the plan is unlimited
for that counter, and `remaining` is null alongside it — deliberately **not**
`0`, which would read as exhausted. Through `JSONSerialization` that null is
`NSNull`, so `searches["remaining"] as? Int` yields `nil` for an unlimited
counter *and* for a missing one. Test `is NSNull` first, as the example above
does.

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.setSenderAddress(_:)`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **Swift Package** — https://github.com/Misar-AI/misarreach-swift

MIT © [Misar AI](https://misar.io)
