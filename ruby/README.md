# MisarReach Ruby SDK

> Ruby client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![Gem Version](https://img.shields.io/gem/v/misarreach.svg)](https://rubygems.org/gems/misarreach)
[![Downloads](https://img.shields.io/gem/dt/misarreach.svg)](https://rubygems.org/gems/misarreach)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**17 resource groups · 94 operations**

Works on Ruby 2.7+ with **no runtime dependencies** — pure `Net::HTTP`, hashes in and
hashes out — so it drops into a Rails app, a Sidekiq worker or a bare script without
pulling anything else onto the load path. Talks to `https://api.misar.io/reach/api`.

---

## Install

```bash
gem install misarreach
```

Or in a `Gemfile`:

```ruby
gem "misarreach", "~> 1.0"
```

Requires Ruby >= 2.7.

**The gem name and the require path differ.** The gem is published as
`misarreach` (no underscore), but the file it installs is `misar_reach.rb` and
the namespace is `MisarReach`. So the true pairing is:

```bash
gem install misarreach     # ← no underscore
```

```ruby
require "misar_reach"      # ← underscore. `require "misarreach"` raises LoadError.
```

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```ruby
require "misar_reach"

reach = MisarReach::Client.new(api_key: ENV.fetch("MISARREACH_API_KEY"))
```

`api_key:` is a required **keyword** and must be non-empty — a positional
argument raises `ArgumentError`. `MisarReach.new(api_key: …)` is shorthand for
the same constructor. `base_url:`, `timeout:` and `max_retries:` are optional.

---

## Quick start

```ruby
require "misar_reach"

reach = MisarReach::Client.new(api_key: ENV.fetch("MISARREACH_API_KEY"))

job = reach.leads.search(query: "CTOs at Series A fintech", useAI: true)
snapshot = reach.leads.job(job["jobId"])

puts snapshot["job"]["status"], snapshot["results"].length
```
---

## What's in the package

- `MisarReach::Client` — constructed with **keyword arguments**
  (`api_key:`, `base_url:`, `timeout:`, `max_retries:`); `api_key` is required
  and a positional key raises `ArgumentError`. `MisarReach.new(api_key: …)` is a
  shorthand for the same thing.
- **Resource accessors** hang off the client as readers: `leads`, `deals`,
  `pipeline`, `channels`, `autopilot`, `sales_agent`, `campaigns`, `contacts`,
  `conversations`, `workspaces`, `settings`, `ads`, `campaign_templates`,
  `deliverability`, `notifications`, `webhooks`, `plan`.
- **Resource classes**, all public constants under `MisarReach`:
  `LeadsResource`, `DealsResource`, `PipelineResource`, `ChannelsResource`,
  `AutopilotResource`, `SalesAgentResource`, `CampaignsResource`,
  `ContactsResource`, `ConversationsResource`, `WorkspacesResource`,
  `SettingsResource`, `AdsResource`, `CampaignTemplatesResource`,
  `DeliverabilityResource`, `NotificationsResource`, `WebhooksResource`,
  `PlanResource`. Note there is **no separate lead-finder resource**: the whole
  `/lead-finder` surface lives on `client.leads`.
- **No models.** Every call returns the parsed JSON as a plain `Hash` with
  **string keys**, matching the open-shape API contract — so it is
  `deal["deal"]["id"]`, never `deal[:deal]`. A non-object JSON body is wrapped
  as `{ "data" => … }`, and a `204` returns `{}`.
- **Errors** — `MisarReach::ApiError` and the typed subclasses below.
- **Transport** — pure `Net::HTTP`, **no runtime dependencies**. `Bearer` auth,
  and automatic retries with exponential back-off on 429/500/502/503/504
  (`max_retries:`, default 3, honouring `Retry-After`). A 402 plan refusal is
  never retried. A *legacy* 429 carrying `upgrade: true` is retried like any
  other 429 before the typed error surfaces, so budget for the back-off.
  Streams are never retried: replaying one that failed mid-flight would
  duplicate whatever the caller already consumed.
- **SSE streaming** for lead-finder job progress, via a block-yielding
  `leads.stream_job`. The server sends *named* events — `progress`, `found`,
  `complete`, `error`, `timeout` — plus a `: keepalive` comment every 20
  seconds, which the parser discards. There is no `[DONE]` sentinel; the block
  simply stops being called when the server closes the stream. A job that has
  **already finished** is answered with a JSON snapshot rather than a stream,
  and the SDK synthesises the terminal `complete` — or `error` when the job
  failed — so a caller that assumed a stream does not hang on nothing.

---

## Resources

Every public method, grouped the way the client groups them.

### Lead finder

23-source search, enrichment, verification, scoring, lists and the SSE job stream.

| Method | Description |
|--------|-------------|
| `account` | Lead-finder credit balance and provider account state. |
| `config` | Which sources, filters and AI options this workspace may use. |
| `list` | Saved leads, paginated, newest first. |
| `search` | Start an async search across 23 sources — returns a `jobId`, not leads. |
| `discover` | Company and lead discovery by firmographic filters. |
| `enrich` | Enrich a saved lead from external data (spends credits). |
| `verify` | Verify email deliverability for one address or a batch (spends credits). |
| `score` | AI-score leads by job id or an explicit lead-id list. |
| `export` | Export saved leads as CSV or JSON. |
| `search_history` | Past searches with their result counts. |
| `recommendations` | Suggested next leads based on what you have already saved. |
| `preview_message` | Draft the AI outreach message for a lead without sending it. |
| `send_to_campaign` | Push selected leads into an existing campaign. |
| `add_to_segment` | Add selected leads to a contact segment. |
| `company` | Company profile for a domain. |
| `company_people` | People found at that company. |
| `lists` | Lead lists in the workspace. |
| `create_list` | Create a lead list. |
| `sync_list` | Sync a lead list to its connected destination. |
| `saved_searches` | Saved search definitions. |
| `create_saved_search` | Save a search for reuse. |
| `delete_saved_search` | Delete a saved search. |
| `scoring_rules` | Lead-scoring rules for this workspace. |
| `create_scoring_rule` | Create a lead-scoring rule. |
| `update_scoring_rule` | Update a lead-scoring rule. |
| `delete_scoring_rule` | Delete a lead-scoring rule. |
| `job` | Poll a search job for status and the results so far. |
| `job_feedback` | Rate a job's results so scoring improves. |
| `stream_job` | SSE progress for a running job — named events, no `[DONE]` sentinel. |

### Deals

CRM deals, their activity log and AI next steps.

| Method | Description |
|--------|-------------|
| `list` | List CRM deals with a workspace revenue summary. |
| `create` | Create a CRM deal. |
| `update` | Update a deal. |
| `delete` | Delete a deal. |
| `activity` | Activity log for a deal. |
| `bulk` | Delete, move or tag many deals at once; tag writes are atomic server-side. |
| `suggestions` | AI next-step suggestions for a deal. |

### Pipeline

The Kanban board and stage moves.

| Method | Description |
|--------|-------------|
| `get` | Kanban board of deals grouped by stage, with revenue totals. |
| `update` | Move a deal to another stage. |

### Campaigns

Multi-step sequences and recipient dispatch.

| Method | Description |
|--------|-------------|
| `list` | List campaigns with step counts and send-status summaries. |
| `create` | Create a campaign with an optional step sequence. |
| `get` | Read one campaign. |
| `update` | Update a campaign. |
| `delete` | Delete a campaign. |
| `enqueue` | Queue recipients; check `warnings` for steps that can never deliver. |

### Campaign templates

Reusable starting points.

| Method | Description |
|--------|-------------|
| `list` | Built-in templates plus your saved ones. |
| `create` | Save a template from steps or by copying a campaign. |

### Contacts

The audience behind outreach.

| Method | Description |
|--------|-------------|
| `list` | List contacts. |
| `create` | Create a contact. |
| `get` | Read one contact. |
| `update` | Update a contact. |
| `delete` | Delete a contact. |
| `bulk` | Bulk delete / unsubscribe / resubscribe, max 500. |
| `import_contacts` | Import up to 5000 contacts; `subscribed` requires consent evidence. |
| `segments` | Segments defined in the workspace. |
| `stats` | Audience counts and subscription health. |

### Conversations

The unified inbox.

| Method | Description |
|--------|-------------|
| `list` | Unified inbox — one row per contact, across every channel. |
| `get` | One contact's full timeline. |
| `reply` | Send a human reply into a thread. |

### Channels

Connectors, consent links and per-channel health.

| Method | Description |
|--------|-------------|
| `status` | Connection state, credential health and period usage per channel. |
| `update_status` | Enable or disable a channel. |
| `opt_in_links` | Double opt-in links to collect SMS/WhatsApp consent. |
| `connect_sms` | Connect BYO Twilio SMS. |
| `connect_whatsapp` | Connect WhatsApp Business. |
| `connect_telegram` | Connect a Telegram bot. |
| `connect_twitter` | Connect X (Twitter) DMs. |
| `connect_instagram` | Connect Instagram DMs. |
| `connect_facebook` | Connect Facebook Messenger. |
| `connect_discord` | Connect a Discord bot. |
| `subscribe_push` | Register a browser web-push subscription. |
| `unsubscribe_push` | Unsubscribe this browser from web push. |

### AI sales agent

Config, today's actions, and running the agent over a thread.

| Method | Description |
|--------|-------------|
| `config` | Agent config — offer, booking link, daily reply cap, confidence threshold. |
| `update_config` | Update the agent config. |
| `actions` | What the agent did today. |
| `conversations` | Conversations the agent is handling. |
| `process` | Run the agent over one conversation. |

### Autopilot

Goal-driven runs.

| Method | Description |
|--------|-------------|
| `start` | Start an autopilot run from a stated goal. |
| `runs` | List autopilot runs, with the caller's plan limits. |
| `get` | Read one autopilot run. |
| `status` | Poll a run's status. |
| `set_status` | Pause, resume or stop a run. |

### Deliverability

Sender reputation.

| Method | Description |
|--------|-------------|
| `get` | Sender health: bounce and complaint rates against *attempted* sends, plus a verdict. |

### Notifications

The in-app bell.

| Method | Description |
|--------|-------------|
| `list` | In-app notifications, newest first, with the unread count. |
| `mark_read` | Mark notifications read — `{ids: [...]}` or `{all: true}`. |

### Webhooks

Signed outbound endpoints.

| Method | Description |
|--------|-------------|
| `list` | Registered endpoints and their delivery health. |
| `create` | Register an endpoint; the signing secret is returned once only. |

### Workspaces

Teams and membership.

| Method | Description |
|--------|-------------|
| `list` | Workspaces you belong to. |
| `create` | Create a workspace. |
| `members` | List members. |
| `add_member` | Invite a member. |
| `remove_member` | Remove a member. |

### Plan

Caps and usage.

| Method | Description |
|--------|-------------|
| `get` | Plan, caps, per-feature usage and the upgrade offer. |

### Settings

Compliance settings.

| Method | Description |
|--------|-------------|
| `sender_address` | The CAN-SPAM postal address on file. |
| `set_sender_address` | Set the CAN-SPAM postal address — sends are blocked until this exists. |

### Ads

Paid-audience export.

| Method | Description |
|--------|-------------|
| `linkedin_company_audience` | Build a LinkedIn company audience from your leads. |

---

## Usage

### Find leads

`leads.search` returns a job id, not leads — the search runs asynchronously.
`location` and `companySize` are **nested under `filters`**, not top level.

```ruby
job = reach.leads.search(
  query: "heads of ops at logistics startups",
  useAI: true,
  filters: { location: "Berlin", companySize: "11-50" },
)
job_id = job["jobId"]
```

### Stream job progress

`stream_job` requires a block and blocks the calling thread until the server
closes the stream.

```ruby
reach.leads.stream_job(job_id) do |evt|
  case evt[:event]
  when "progress"          then puts "working #{evt[:data]["message"]}"
  when "found"             then puts "hit #{evt[:data]["email"]}"
  when "complete"          then puts "done, #{evt[:data]["total_found"]} found"
  when "error", "timeout"  then warn "#{evt[:event]}: #{evt[:data]}"
  end
end
```

Each event is a `Hash` with a **symbol** `:event` / `:data` pair — the only
symbol-keyed structure in the SDK — while `:data` is the decoded JSON payload
with string keys.

### List saved leads

```ruby
page = reach.leads.list(page: 1, limit: 50)
puts page["total"]
```

### Create a CRM contact and a deal

```ruby
require "time" # Time#iso8601 lives in the stdlib, not in core

reach.contacts.create(
  email: "cto@acme.com",
  firstName: "Dana",
  status: "subscribed",
  consent: { source: "signup form /pricing", timestamp: Time.now.utc.iso8601 },
)

created = reach.deals.create(
  leadEmail: "cto@acme.com",
  leadName: "Dana Reyes",
  value: 12_000,
  currency: "USD",
)
deal_id = created["deal"]["id"]
```

### Read and move the pipeline

The board is keyed by stage; every stage in `stages` is present, possibly empty.
Moving a deal is `pipeline.update`, not `pipeline.move`.

```ruby
board = reach.pipeline.get
puts board["stages"].inspect, board["revenue"]["pipeline"]

reach.pipeline.update(dealId: deal_id, newStage: "meeting")
```

### Run a campaign

```ruby
campaign = reach.campaigns.create(
  name: "Q3 fintech outbound",
  steps: [
    # Steps are flat and ORDERED BY ARRAY INDEX — the server assigns
    # step_order and builds the template itself. There is no nested `template`.
    { channel: "email", subject: "Quick question", body: "Hi {{name}} …" },
    { channel: "email", delay_hours: 72, body: "Following up …" },
  ],
)

result = reach.campaigns.enqueue(
  campaign["id"],
  recipients: [{ email: "cto@acme.com", name: "Dana Reyes", company: "Acme" }],
)

# Check `warnings`: a step whose channel has no inbound path in this deployment
# can never deliver, and the server reports that here rather than silently
# dropping every recipient at dispatch time.
puts result["queued"], result["skipped"], result["warnings"].inspect
```

### Check the plan before an expensive run

```ruby
plan = reach.plan.get
searches = plan["usage"]["lead_searches"]

if searches["remaining"].nil?
  puts "unlimited lead searches on #{plan["plan"]["name"]}"
elsif searches["remaining"].zero?
  puts "no searches left; upgrade at #{plan["upgrade"]["url"]}"
else
  puts "#{searches["remaining"]} of #{searches["limit"]} searches left"
end
```

### Reply into a conversation

The reply body field is `message`, and the thread's own channel decides the
transport — you do not pick it.

```ruby
inbox = reach.conversations.list(limit: 25)
puts inbox["conversations"].length

reach.conversations.reply(
  "cto@acme.com",
  message: "Happy to walk you through it — does Thursday work?",
)
```

---

## Errors

Every non-2xx raises `MisarReach::ApiError` or one of its subclasses — all of
which descend from `ApiError`, and so from `StandardError`. Each carries
`status` and `code`; the HTTP ones also carry the decoded response `body`
(`NetworkError` has no response, so its `body` is `nil`).

| Class | Raised for |
|-------|-----------|
| `MisarReach::AuthError` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `MisarReach::NotFoundError` | 404 |
| `MisarReach::RateLimitError` | 429 rate limiting; adds `retry_after`, `balance`, `free_remaining` |
| `MisarReach::UpgradeRequiredError` | a plan cap was hit — see below |
| `MisarReach::ApiError` | any other non-2xx; the base class of all of the above |
| `MisarReach::NetworkError` | transport failure or retries exhausted; `status` is `0` |

The same mapping applies to the SSE stream, so a plan refusal on `stream_job`
arrives as the same typed error rather than a bare exception.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces immediately:

```ruby
begin
  reach.leads.search(query: "…")
rescue MisarReach::UpgradeRequiredError => e
  # e.g. feature "lead_searches", current 50 of limit 50
  warn "#{e.feature}: #{e.current}/#{e.limit}"
  warn "upgrade at #{e.upgrade_url}" # resolved to an absolute URL
end
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments — though `e.status` then reports `402`, the canonical status
for the condition, rather than the wire status. This is distinct from the 503
`retry: true` the server sends when it could not *check* the quota — that one is
retried, so "we don't know" is never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get`, a `usage` entry's `limit` is `nil` when the plan is unlimited for
that counter, and `remaining` is `nil` alongside it — deliberately **not** `0`,
which would read as exhausted. Test with `.nil?` before comparing, as the
example above does; `searches["remaining"].zero?` on a `nil` raises
`NoMethodError`.

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.set_sender_address`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **RubyGems** — https://rubygems.org/gems/misarreach

MIT © [Misar AI](https://misar.io)
