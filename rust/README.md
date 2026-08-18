# MisarReach Rust SDK

> Async Rust client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![crates.io](https://img.shields.io/crates/v/misarreach.svg)](https://crates.io/crates/misarreach)
[![docs.rs](https://img.shields.io/docsrs/misarreach)](https://docs.rs/misarreach)
[![License](https://img.shields.io/crates/l/misarreach.svg)](./LICENSE)

**17 resource groups · 94 operations**

Works with any `tokio` runtime on Rust 2021. `reqwest` for transport,
`serde_json::Value` in and out to match the open-shape API contract, and a
callback-driven SSE reader for lead-search progress. Talks to
`https://api.misar.io/reach/api`.

---

## Install

```toml
[dependencies]
misarreach = "5.0.1"
tokio = { version = "1", features = ["full"] }
serde_json = "1"
```

Edition 2021. Every method is `async` and needs a `tokio` runtime.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```rust
use misarreach::MisarReachClient;

let client = MisarReachClient::new(&std::env::var("MISARREACH_API_KEY").unwrap());
```

`new()` returns `Self`, not a `Result` — construction cannot fail and the key is
not validated locally, so a bad key first surfaces as `ReachError::Api { status:
401, .. }` on the first call. `with_base_url()` and `with_max_retries()` consume
the client and rebuild it, so chain them at construction:

```rust
let client = MisarReachClient::new("mrk_your_key")
    .with_base_url("https://api.misar.io/reach/api")
    .with_max_retries(5);
```

---

## Quick start

```rust
use misarreach::{MisarReachClient, ReachError};
use serde_json::json;

#[tokio::main]
async fn main() -> Result<(), ReachError> {
    let reach = MisarReachClient::new(&std::env::var("MISARREACH_API_KEY").unwrap());

    let job = reach.leads.search(json!({
        "query": "CTOs at Series A fintech",
        "useAI": true,
    })).await?;

    let job_id = job["jobId"].as_str().unwrap();
    let snapshot = reach.leads.job(job_id).await?;

    println!("{} {}", snapshot["job"]["status"], snapshot["results"].as_array().unwrap().len());
    Ok(())
}
```
---

## What's in the package

- `MisarReachClient` — built with `MisarReachClient::new(api_key)`. It returns
  `Self`, **not** a `Result`: construction cannot fail and the key is not
  validated locally, so a bad key first shows up as an `Api { status: 401 }` on
  the initial call. `with_base_url()` and `with_max_retries()` consume the
  client and rebuild it, so chain them at construction rather than later.
- **17 resource structs**, each a public field on the client and each exported
  by name so you can hold one in your own type: `LeadsResource`,
  `DealsResource`, `PipelineResource`, `ChannelsResource`, `AutopilotResource`,
  `SalesAgentResource`, `CampaignsResource`, `ContactsResource`,
  `ConversationsResource`, `CampaignTemplatesResource`, `DeliverabilityResource`,
  `NotificationsResource`, `WebhooksResource`, `WorkspacesResource`,
  `PlanResource`, `SettingsResource`, `AdsResource`. Together they carry 94
  async methods covering all 94 operations in the OpenAPI spec.
- **`serde_json::Value` in, `serde_json::Value` out.** Every resource method
  takes a `Value` body or query object and resolves to `Result<Value,
  ReachError>`. This matches the open-shape API contract, at the cost of no
  compile-time field checking.
- **Optional typed models** in the `types` module (`Lead`, `LeadJob`, `Deal`,
  `Contact`, `Campaign`, `AutopilotRun`, `ChannelStatus`, `PipelineStage`, …).
  They are `Serialize + Deserialize` conveniences you opt into with
  `serde_json::from_value`; no resource method returns one directly.
- **Errors** — the single `ReachError` enum, re-exported at the crate root.
- **Transport** — `reqwest` with a 30-second timeout and a `Bearer` header, and
  automatic retries with exponential back-off on 429, 500, 502, 503 and 504 —
  200 ms before the second attempt, doubling thereafter. `max_retries` is the
  total attempt count, not the number of extra tries, and defaults to 3. A 402
  plan refusal is never retried.
- **SSE streaming** for lead-finder job progress, via a **callback**, not a
  `Stream`: `leads.stream(job_id, |ev| …)` drives the connection itself and
  resolves when the server closes it, so you need no `futures_util` /
  `StreamExt` import of your own. Each frame arrives as a `ReachSseEvent` with
  `event`, `data` and `raw`. The server sends *named* events — `progress`,
  `found`, `complete`, `error`, `timeout` — plus a `: keepalive` comment every
  20 seconds, which is filtered out. There is no `[DONE]` sentinel; the call
  simply returns. A job that has **already finished** is answered with a JSON
  snapshot rather than a stream, and the SDK synthesises the terminal
  `complete`/`error` frame so a caller that assumed a stream does not hang on
  nothing. Streams are never retried — replaying one that failed mid-flight
  would duplicate what the caller already consumed.

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
| `search_history()` | Past searches with their result counts. |
| `preview_message()` | Draft the AI outreach message for a lead without sending it. |
| `send_to_campaign()` | Push selected leads into an existing campaign. |
| `add_to_segment()` | Add selected leads to a contact segment. |
| `company()` | Company profile for a domain. |
| `company_people()` | People found at that company. |
| `job()` | Poll a search job for status and the results so far. |
| `job_feedback()` | Rate a job's results so scoring improves. |
| `stream()` | SSE progress for a running job — named events, no `[DONE]` sentinel. |
| `lists()` | Lead lists in the workspace. |
| `create_list()` | Create a lead list. |
| `sync_list()` | Sync a lead list to its connected destination. |
| `saved_searches()` | Saved search definitions. |
| `create_saved_search()` | Save a search for reuse. |
| `delete_saved_search()` | Delete a saved search. |
| `scoring_rules()` | Lead-scoring rules for this workspace. |
| `create_scoring_rule()` | Create a lead-scoring rule. |
| `update_scoring_rule()` | Update a lead-scoring rule. |
| `delete_scoring_rule()` | Delete a lead-scoring rule. |

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
| `import_contacts()` | Import up to 5000 contacts; `subscribed` requires consent evidence. |
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
| `update_status()` | Enable or disable a channel. |
| `opt_in_links()` | Double opt-in links to collect SMS/WhatsApp consent. |
| `connect_sms()` | Connect BYO Twilio SMS. |
| `connect_whatsapp()` | Connect WhatsApp Business. |
| `connect_telegram()` | Connect a Telegram bot. |
| `connect_twitter()` | Connect X (Twitter) DMs. |
| `connect_instagram()` | Connect Instagram DMs. |
| `connect_facebook()` | Connect Facebook Messenger. |
| `connect_discord()` | Connect a Discord bot. |
| `subscribe_push()` | Register a browser web-push subscription. |
| `unsubscribe_push()` | Unsubscribe this browser from web push. |

### AI sales agent

Config, today's actions, and running the agent over a thread.

| Method | Description |
|--------|-------------|
| `config()` | Agent config — offer, booking link, daily reply cap, confidence threshold. |
| `update_config()` | Update the agent config. |
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
| `update_status()` | Pause, resume or stop a run. |

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
| `mark_read()` | Mark notifications read — `{ids: [...]}` or `{all: true}`. |

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
| `add_member()` | Invite a member. |
| `remove_member()` | Remove a member. |

### Plan

Caps and usage.

| Method | Description |
|--------|-------------|
| `get()` | Plan, caps, per-feature usage and the upgrade offer. |

### Settings

Compliance settings.

| Method | Description |
|--------|-------------|
| `get_sender_address()` | The CAN-SPAM postal address on file. |
| `set_sender_address()` | Set the CAN-SPAM postal address — sends are blocked until this exists. |

### Ads

Paid-audience export.

| Method | Description |
|--------|-------------|
| `linkedin_company_audience()` | Build a LinkedIn company audience from your leads. |

---

## Usage

### Find leads

`leads.search()` returns a job id, not leads — the search runs asynchronously
and answers `202`.

```rust
let job = reach.leads.search(json!({
    "query": "heads of ops at logistics startups",
    "useAI": true,
    "filters": { "location": "Berlin", "companySize": "11-50" },
})).await?;

let job_id = job["jobId"].as_str().unwrap().to_string();
```

### Stream job progress

`stream()` takes a `FnMut(ReachSseEvent)` and resolves when the server closes
the connection. Switch on `ev.event` — without the name you cannot tell
completion from progress.

```rust
use std::sync::{Arc, Mutex};

let found = Arc::new(Mutex::new(0_i64));
let sink = Arc::clone(&found);

reach.leads.stream(&job_id, move |ev| match ev.event.as_str() {
    "progress" => println!("working: {}", ev.data["message"]),
    "found"    => *sink.lock().unwrap() = ev.data["total_found"].as_i64().unwrap_or(0),
    "complete" => println!("done: {}", ev.data),
    "error" | "timeout" => eprintln!("{}: {}", ev.event, ev.data),
    _ => {}
}).await?;
```

The closure is `FnMut`, so it must own or share what it writes into — a bare
`&mut` borrow held across the `await` will not compile. There is no cancellation
handle: to stop early, wrap the call in `tokio::time::timeout` or drop the task.

### List saved leads

```rust
let page = reach.leads.leads(json!({ "page": 1, "limit": 50 })).await?;
println!("{} total", page["total"]);
```

Query objects are flattened to query-string pairs; nested objects and arrays are
dropped, so pass scalars only.

### Create a CRM contact and a deal

```rust
reach.contacts.create(json!({
    "email": "cto@acme.com",
    "firstName": "Dana",
    "status": "subscribed",
    "consent": { "source": "signup form /pricing", "timestamp": "2026-08-19T09:00:00Z" },
})).await?;

let created = reach.deals.create(json!({
    "leadEmail": "cto@acme.com",
    "leadName": "Dana Reyes",
    "value": 12000,
    "currency": "USD",
})).await?;

let deal_id = created["deal"]["id"].as_str().unwrap().to_string();
```

`contacts.create()` is a pass-through to the audience service, so it applies no
schema of its own and the accepted fields are defined there.

### Read and move the pipeline

`pipeline.get()` returns the Kanban board. `pipeline.create()` is named for its
HTTP verb, not its effect — `POST /pipeline` **moves a deal to another stage**,
and that is the only thing it does.

```rust
let board = reach.pipeline.get(json!({})).await?;
println!("open pipeline: {}", board["revenue"]["pipeline"]);

reach.pipeline.create(json!({ "dealId": deal_id, "newStage": "meeting" })).await?;
```

Valid stages are `new`, `contacted`, `interested`, `meeting`, `proposal`,
`closed` and `lost`.

### Run a campaign

Steps are **ordered by array index** — the index becomes `step_order` — and each
carries its channel, delay and body inline.

```rust
let campaign = reach.campaigns.create(json!({
    "name": "Q3 fintech outbound",
    "steps": [
        { "channel": "email", "subject": "Quick question", "body": "Hi {{name}} …" },
        { "channel": "email", "delay_hours": 72, "body": "Following up …" },
    ],
})).await?;

let result = reach.campaigns.enqueue(
    campaign["id"].as_str().unwrap(),
    json!({ "recipients": [{ "email": "cto@acme.com", "name": "Dana Reyes" }] }),
).await?;

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
println!("{} queued, {} skipped, {}", result["queued"], result["skipped"], result["warnings"]);
```

### Check the plan before an expensive run

```rust
let plan = reach.plan.get().await?;
let searches = &plan["usage"]["lead_searches"];

if searches["remaining"].is_null() {
    println!("unlimited lead searches on {}", plan["plan"]["name"]);
} else if searches["remaining"] == 0 {
    println!("no searches left; upgrade at {}", plan["upgrade"]["url"]);
}
```

`usage` is keyed by `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals` and `linkedin_seats`. Plan slugs are `free`, `starter`, `pro`
and `scale`.

### Reply into a conversation

The reply body field is `message`, and it is required.

```rust
let inbox = reach.conversations.list(json!({ "limit": 25 })).await?;
println!("{} threads", inbox["conversations"].as_array().unwrap().len());

reach.conversations.reply("cto@acme.com", json!({
    "message": "Happy to walk you through it — does Thursday work?",
})).await?;
```

The response's `channel` tells you which transport actually carried it.

---

## Errors

Every failure is one `ReachError` enum — there are no per-status types, so
match on the variant and then on `status`.

| Variant | Returned for |
|---------|-------------|
| `Api { status, message }` | any non-2xx that is not a plan refusal — including **401/403** for a missing, invalid or out-of-scope `mrk_` key, and **404**. `message` is pulled out of the `{"error":{"message"}}` envelope, falling back to a bare `message`/`error` string, then to the raw body |
| `UpgradeRequired { status, message, feature, limit, current, upgrade_url }` | a plan cap was hit — see below |
| `Network(reqwest::Error)` | transport failure, timeout, or retries exhausted |
| `Json(serde_json::Error)` | a 2xx body that was not valid JSON |

The same mapping applies to the SSE stream, so a plan refusal on
`leads.stream()` arrives as `UpgradeRequired`, not a bare `Api`.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces immediately, on read and write routes alike:

```rust
match reach.leads.search(json!({ "query": "…" })).await {
    Ok(job) => println!("{}", job["jobId"]),
    Err(ReachError::UpgradeRequired { feature, current, limit, .. }) => {
        // e.g. feature "lead_searches", current 50 of limit 50
        eprintln!("{:?}: {:?}/{:?}", feature, current, limit);
    }
    Err(other) => return Err(other),
}
```

`upgrade_url` arrives app-relative (`/settings?tab=billing`) and is resolved
against `https://misarreach.com` before you see it. `ReachError::upgrade_url()`
reads it off any error and returns `None` for the other variants:

```rust
if let Some(url) = err.upgrade_url() {
    eprintln!("upgrade at {url}");
}
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments. This is distinct from the 503 `retry: true` the server sends
when it could not *check* the quota — that one carries no `upgrade` flag and is
retried, so "we don't know" is never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Because everything is a `serde_json::Value`,
`as_i64()` returns `None` for both `null` and a non-number: test `is_null()`
first, or `unwrap_or(0)` will silently turn "unlimited" into "exhausted".

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.set_sender_address()`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **Crates.io** — https://crates.io/crates/misarreach

MIT © [Misar AI](https://misar.io)
