# MisarReach Python SDK

Python client for the [MisarReach](https://misarreach.com) developer API.

MisarReach is an outreach and lead-generation platform. You describe the buyer
you want in plain language; its lead finder runs an asynchronous search across
23 sources, then enriches, verifies and AI-scores what comes back. Those leads
land in a built-in CRM — contacts, deals, a Kanban pipeline — and go out through
multi-step campaigns that dispatch over email, SMS, WhatsApp, web push and
social DMs, with an AI sales agent that drafts replies and an autopilot that
runs the whole loop from a stated goal. This SDK is the sync-and-async client
for that API (`https://api.misar.io/reach/api`), for anyone wiring MisarReach
into a backend service, a data pipeline or a scheduled job.

Full reference: [`docs.misar.io/reach`](https://docs.misar.io/reach) · OpenAPI:
`openapi/reach.openapi.json`.

## Features

- **Lead finder** — `leads.search()` starts an async job across 23 sources and
  returns a `jobId`; poll it with `leads.get_job()` or watch it live over SSE.
  Also company discovery, Hunter.io enrichment, email verification, on-demand AI
  scoring, saved searches, scoring rules, lead lists, search history,
  recommendations, export, and AI message preview.
- **Contacts** — CRUD, segments, stats, bulk unsubscribe/resubscribe/delete, and
  import of up to 5000 contacts. A contact may only be imported as `subscribed`
  *with* consent evidence; without it the server downgrades the status.
- **Deals & pipeline** — list/create/update/delete, activity log, AI next-step
  suggestions, the Kanban board grouped by stage, and stage moves.
- **Campaigns** — multi-step sequences with a channel and delay per step,
  recipients enqueued directly or by lead id, plus reusable campaign templates.
- **Channels** — status and delivery stats for WhatsApp, SMS and web push;
  connectors for BYO Twilio SMS, WhatsApp Business, Telegram, Instagram,
  Facebook, X and Discord; push subscriptions; double opt-in links.
- **Conversations** — a unified inbox with one row per contact across every
  channel, each contact's full timeline, and human replies into a thread.
- **AI sales agent** — read and update the agent config, read today's actions,
  and run the agent over a single conversation.
- **Autopilot** — start a run from a goal, list runs, poll status, stop.
- **Deliverability** — sender health over a rolling window: bounce and complaint
  rates against *attempted* sends, with a verdict encoding the Gmail/Yahoo
  bulk-sender rules.
- **Plan, notifications, webhooks, workspaces, settings, ads** — live plan caps
  and usage, the notification bell, signed webhook endpoints, workspace members,
  the CAN-SPAM sender address, and LinkedIn company audiences.

## What's in the package

- `MisarReachClient(api_key, base_url=…, max_retries=3, timeout=30.0)` — resource
  accessors hang off the instance: `client.leads`, `client.deals`,
  `client.pipeline`, `client.channels`, `client.autopilot`,
  `client.sales_agent`, `client.campaigns`, `client.contacts`,
  `client.conversations`, `client.settings`, `client.workspaces`, `client.ads`,
  `client.lead_finder`, `client.campaign_templates`, `client.deliverability`,
  `client.notifications`, `client.plan`, `client.webhooks`.
- **Sync and async in one client.** Every method has an `a`-prefixed async twin
  — `leads.search()` / `leads.asearch()`, `deals.list()` / `deals.alist()`.
- `SSEEvent` — a dataclass with `.event` and `.data`.
- **Errors** — `ReachError` and the typed subclasses below.
- **Transport** — `httpx`, `Bearer` auth, and automatic retries with exponential
  back-off on 429/500/502/503/504 (`max_retries`, default 3). A 402 plan refusal
  is *not* retried; nor is a 429 carrying `upgrade: true`, which the retry loop
  inspects the body to tell apart from genuine rate limiting.
- **SSE streaming** for lead-finder job progress. The server sends *named*
  events — `progress`, `found`, `complete`, `error`, `timeout` — plus a
  `: keepalive` comment every 20 seconds. There is no `[DONE]` sentinel; the
  iterator simply ends when the server closes the stream. A job that has
  **already finished** is answered with a JSON snapshot rather than a stream,
  and the SDK yields the terminal `complete`/`error` event in its place, so a
  caller that assumed a stream does not hang on nothing.

## Install

```bash
pip install misar-reach==5.0.1
```

Requires Python 3.9+. The distribution is named `misar-reach`; the import name
is `misar_reach`.

## Quick start

```python
from misar_reach import MisarReachClient

client = MisarReachClient("mrk_your_key")

job = client.leads.search({"query": "CTOs at Series A fintech", "useAI": True})
snapshot = client.leads.get_job(job["jobId"])
print(snapshot["job"]["status"], len(snapshot["results"]))
```

Create an API key in **Settings → API keys**; it starts with `mrk_` and is
validated only against the reach-owned key table, so a key from another Misar
product is rejected.

## Primary functions

### Find leads

`leads.search()` returns a job id, not leads — the search runs asynchronously.

```python
job = client.leads.search({
    "query": "heads of ops at logistics startups",
    "useAI": True,
    "filters": {"location": "Berlin", "companySize": "11-50"},
})
job_id = job["jobId"]
```

### Stream job progress

```python
for evt in client.leads.stream_job(job_id):
    if evt.event == "progress":
        print("working", evt.data)
    elif evt.event == "found":
        print("hit", evt.data)
    elif evt.event in ("complete", "error", "timeout"):
        print(evt.event, evt.data)
        break
```

The async twin is `astream_job()`:

```python
import asyncio

async def main():
    client = MisarReachClient("mrk_your_key")
    res = await client.leads.asearch({"query": "fintech CFOs"})
    async for evt in client.leads.astream_job(res["jobId"]):
        print(evt.event, evt.data)

asyncio.run(main())
```

### List saved leads

```python
page = client.leads.list(page=1, limit=50)
print(page["total"])
```

### Create a CRM contact and a deal

```python
from datetime import datetime, timezone

client.contacts.create({
    "email": "cto@acme.com",
    "firstName": "Dana",
    "status": "subscribed",
    "consent": {
        "source": "signup form /pricing",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    },
})

deal = client.deals.create({
    "leadEmail": "cto@acme.com",
    "leadName": "Dana Reyes",
    "value": 12000,
    "currency": "USD",
})
```

### Read and move the pipeline

```python
board = client.pipeline.get()
client.pipeline.move({"dealId": deal["deal"]["id"], "newStage": "meeting"})
```

### Run a campaign

```python
campaign = client.campaigns.create({
    "name": "Q3 fintech outbound",
    "steps": [
        # Steps are flat and ORDERED BY ARRAY INDEX — the server assigns
        # step_order and builds the template itself. No nested "template".
        {"channel": "email", "subject": "Quick question", "body": "Hi {{name}} …"},
        {"channel": "email", "delay_hours": 72, "body": "Following up …"},
    ],
})

result = client.campaigns.enqueue(campaign["id"], {
    "recipients": [{"email": "cto@acme.com", "name": "Dana Reyes", "company": "Acme"}],
})

# Check `warnings`: a step whose channel has no inbound path in this deployment
# can never deliver, and the server reports that here rather than silently
# dropping every recipient at dispatch time.
print(result["queued"], result["skipped"], result.get("warnings"))
```

### Check the plan before an expensive run

```python
plan = client.plan.get()
searches = plan["usage"]["lead_searches"]

if searches["remaining"] is None:
    print("unlimited lead searches on", plan["plan"]["name"])
elif searches["remaining"] == 0:
    print("no searches left; upgrade at", plan["upgrade"]["url"])
```

### Reply into a conversation

```python
inbox = client.conversations.list(limit=25)
client.conversations.reply("cto@acme.com", {
    # "message", not "body" — the channel is chosen server-side.
    "message": "Happy to walk you through it — does Thursday work?",
})
```

## Errors

Every non-2xx raises a subclass of `ReachError`.

| Class | Raised for |
|-------|-----------|
| `ReachAuthError` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `ReachNotFoundError` | 404 |
| `ReachRateLimitError` | 429 rate limiting; carries `retry_after` |
| `ReachUpgradeRequiredError` | a plan cap was hit — see below |
| `ReachAPIError` | any other non-2xx; carries `status`, `code`, `error` |
| `ReachNetworkError` | transport failure or retries exhausted |

The same mapping applies to the SSE stream, so a plan refusal on `stream_job()`
arrives as the same typed error, not a bare exception.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces immediately:

```python
from misar_reach import ReachUpgradeRequiredError

try:
    client.leads.search({"query": "…"})
except ReachUpgradeRequiredError as err:
    # e.g. feature "lead_searches", current 50 of limit 50
    print(f"{err.feature}: {err.current}/{err.limit}")
    print("upgrade at", err.upgrade_url)  # resolved to an absolute URL
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments. This is distinct from the 503 `retry: true` the server sends
when it could not *check* the quota — that one is retried, so "we don't know" is
never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `None` when the plan is unlimited
for that counter, and `remaining` is `None` alongside it — deliberately **not**
`0`, which would read as exhausted. Test with `is None` before comparing.

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings.set_sender_address()`.

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **PyPI** — https://pypi.org/project/misar-reach/

MIT © [Misar AI](https://misar.io)
