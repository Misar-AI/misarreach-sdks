# @misarreach/sdk

TypeScript client for the [MisarReach](https://misarreach.com) developer API.

MisarReach is an outreach and lead-generation platform. You describe the buyer
you want in plain language; its lead finder runs an asynchronous search across
23 sources, then enriches, verifies and AI-scores what comes back. Those leads
land in a built-in CRM — contacts, deals, a Kanban pipeline — and go out through
multi-step campaigns that dispatch over email, SMS, WhatsApp, web push and
social DMs, with an AI sales agent that drafts replies and an autopilot that
runs the whole loop from a stated goal. This SDK is the typed Node/browser
client for that API (`https://api.misar.io/reach/api`), for anyone wiring
MisarReach into a backend, a job runner or an internal tool.

## Features

What the API covers, and what this package exposes:

- **Lead finder** — `leads.search()` starts an async job across 23 sources and
  returns a `jobId`; poll it with `leads.jobStatus()` or watch it live over SSE.
  Also company discovery, Hunter.io enrichment, email verification, on-demand AI
  scoring, saved searches, scoring rules, lead lists, search history,
  recommendations, CSV/JSON export, and AI message preview.
- **Contacts** — CRUD, segments, stats, bulk unsubscribe/resubscribe/delete, and
  import of up to 5000 contacts. A contact may only be imported as `subscribed`
  *with* consent evidence; without it the server downgrades the status.
- **Deals & pipeline** — list/create/update, activity log, AI next-step
  suggestions, the Kanban board grouped by stage, and stage moves.
- **Campaigns** — multi-step sequences with a channel and delay per step,
  recipients enqueued directly or by lead id, plus reusable campaign templates.
- **Channels** — status and delivery stats for WhatsApp, SMS and web push;
  connectors for BYO Twilio SMS, WhatsApp Business, Telegram, Instagram,
  Facebook, X and Discord; push subscriptions; double opt-in links.
- **Conversations** — a unified inbox with one row per contact across every
  channel, each contact's full timeline, and human replies into a thread.
- **AI sales agent** — read and update the agent config (offer, booking link,
  daily reply cap, confidence threshold), read today's actions, and run the
  agent over a single conversation.
- **Autopilot** — start a run from a goal, list runs, poll status, stop.
- **Deliverability** — sender health over a rolling window: bounce and complaint
  rates against *attempted* sends, with a verdict encoding the Gmail/Yahoo
  bulk-sender rules.
- **Plan, notifications, webhooks, workspaces, settings, ads** — live plan caps
  and usage, the notification bell, signed webhook endpoints, workspace members,
  the CAN-SPAM sender address, and LinkedIn company audiences.

## What's in the package

- `MisarReachClient` — constructed with your API key; resources hang off it as
  getters (`reach.leads`, `reach.deals`, `reach.campaigns`, …).
- **Resource classes**, all exported by name so you can type your own helpers
  against them: `LeadsResource`, `LeadFinderResource`, `DealsResource`,
  `CampaignsResource`, `ContactsResource`, `ConversationsResource`,
  `ChannelsResource`, `SalesAgentResource`, `AutopilotResource`,
  `DeliverabilityResource`, `NotificationsResource`, `WebhooksResource`,
  `WorkspacesResource`, `CampaignTemplatesResource`, `SettingsResource`,
  `AdsResource`, `PlanResource`.
- **Typed models** for the lead, deal, pipeline, channel, sales-agent, autopilot
  and plan payloads (`Lead`, `Deal`, `PipelineBoard`, `PlanResponse`, …). The
  broader surface returns `JsonObject`, matching the open-shape API contract.
- **Errors** — `MisarReachError` and the typed subclasses below.
- **Transport** — one `fetch` per call with a `Bearer` header. Note this client
  does **not** retry: unlike the Python, Go, Ruby, Rust, PHP, Java, Kotlin, C#,
  Swift and Dart SDKs, there is no built-in back-off loop, so wrap calls in your
  own retry policy if you need one.
- **SSE streaming** for lead-finder job progress. The server sends *named*
  events — `progress`, `found`, `complete`, `error`, `timeout` — plus a
  `: keepalive` comment every 20 seconds. There is no `[DONE]` sentinel; the
  iterator simply ends when the server closes the stream. A job that has
  **already finished** is answered with a JSON snapshot rather than a stream,
  and the SDK synthesises the terminal `complete`/`error` frame so a caller that
  assumed a stream does not hang on nothing.

## Install

```bash
npm install @misarreach/sdk@5.0.0
```

Requires Node 18+ (for global `fetch`). ESM only.

## Quick start

```ts
import { MisarReachClient } from "@misarreach/sdk";

// The API key is the first positional argument — not an options object.
const reach = new MisarReachClient(process.env.MISARREACH_API_KEY!);

const { jobId } = await reach.leads.search({
  query: "CTOs at Series A fintech",
  useAI: true,
});

const { job, results } = await reach.leads.jobStatus(jobId);
console.log(job.status, results.length);
```

Create an API key in **Settings → API keys**; it starts with `mrk_`.

## Primary functions

### Find leads

`leads.search()` returns a job id, not leads — the search runs asynchronously.

```ts
const { jobId } = await reach.leads.search({
  query: "heads of ops at logistics startups",
  useAI: true,
  filters: { location: "Berlin", companySize: "11-50" },
});
```

### Stream job progress

```ts
const controller = new AbortController();

for await (const ev of reach.leadFinder.stream(jobId, { signal: controller.signal })) {
  switch (ev.event) {
    case "progress": console.log("working", ev.data); break;
    case "found":    console.log("hit", ev.data); break;
    case "complete": console.log("done", ev.data); break;
    case "error":
    case "timeout":  console.error(ev.event, ev.data); break;
  }
}
```

Pass an `AbortSignal` if you need to stop early — without one, a stuck job holds
the connection open.

### List saved leads

```ts
const { leads, total } = await reach.leads.list({ page: 1, limit: 50 });
```

### Create a CRM contact and a deal

```ts
await reach.contacts.create({
  email: "cto@acme.com",
  firstName: "Dana",
  status: "subscribed",
  consent: { source: "signup form /pricing", timestamp: new Date().toISOString() },
});

const { deal } = await reach.deals.create({
  leadEmail: "cto@acme.com",
  leadName: "Dana Reyes",
  value: 12000,
  currency: "USD",
});
```

### Read and move the pipeline

```ts
const { board, revenue, stages } = await reach.deals.pipeline();
await reach.deals.movePipelineStage({ dealId: deal.id, newStage: "meeting" });
```

### Run a campaign

```ts
const campaign = await reach.campaigns.create({
  name: "Q3 fintech outbound",
  steps: [
    // Steps are flat and ORDERED BY ARRAY INDEX — the server assigns step_order
    // and builds the template itself. There is no nested `template` object.
    { channel: "email", subject: "Quick question", body: "Hi {{name}} …" },
    { channel: "email", delay_hours: 72, body: "Following up …" },
  ],
});

const result = await reach.campaigns.enqueue(campaign.id as string, {
  recipients: [{ email: "cto@acme.com", name: "Dana Reyes", company: "Acme" }],
});

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
console.log(result.queued, result.skipped, result.warnings);
```

### Check the plan before an expensive run

```ts
const plan = await reach.plan.get();
const searches = plan.usage.lead_searches;

if (searches.remaining === null) {
  console.log("unlimited lead searches on", plan.plan.name);
} else if (searches.remaining === 0) {
  console.log("no searches left; upgrade at", plan.upgrade?.url);
}
```

### Reply into a conversation

```ts
const inbox = await reach.conversations.list({ limit: 25 });
await reach.conversations.reply("cto@acme.com", {
  // `message`, not `body` — the channel is chosen server-side.
  message: "Happy to walk you through it — does Thursday work?",
});
```

## Errors

Every non-2xx throws a `MisarReachError` or one of its subclasses. All are
exported from the package root.

| Class | Raised for |
|-------|-----------|
| `AuthError` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `NotFoundError` | 404 |
| `RateLimitError` | 429 rate limiting; carries `balance` and `freeRemaining` |
| `UpgradeRequiredError` | a plan cap was hit — see below |
| `MisarReachError` | any other non-2xx; carries `status` and `code` |

The same mapping applies to the SSE stream, so a plan refusal on
`leadFinder.stream()` arrives as the same typed error, not a bare `Error`.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the client
surfaces it immediately:

```ts
import { UpgradeRequiredError } from "@misarreach/sdk";

try {
  await reach.leads.search({ query: "…" });
} catch (err) {
  if (err instanceof UpgradeRequiredError) {
    // e.g. feature "lead_searches", current 50 of limit 50
    console.error(`${err.feature}: ${err.current}/${err.limit}`);
    console.error("upgrade at", err.upgradeUrl); // resolved to an absolute URL
  }
}
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments. This is distinct from the 503 `retry: true` the server sends
when it could not *check* the quota — that one is safe to retry, so "we don't
know" is never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Test for `null` before comparing.

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.setSenderAddress()`.

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **npm** — https://www.npmjs.com/package/@misarreach/sdk

MIT © [Misar AI](https://misar.io)
