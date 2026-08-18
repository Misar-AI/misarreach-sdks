# MisarReach PHP SDK

> PHP client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![Latest Version](https://img.shields.io/packagist/v/misarai/misarreach-php.svg)](https://packagist.org/packages/misarai/misarreach-php)
[![Downloads](https://img.shields.io/packagist/dt/misarai/misarreach-php.svg)](https://packagist.org/packages/misarai/misarreach-php)
[![License](https://img.shields.io/packagist/l/misarai/misarreach-php.svg)](./LICENSE)

**17 resource groups · 94 operations**

Works on PHP 8.1+ with `ext-curl` and `ext-json` and no Composer runtime
dependencies — arrays in, arrays out. Drops into Laravel, Symfony or a plain
script. Talks to `https://api.misar.io/reach/api`.

---

## Install

```bash
composer require misarai/misarreach-php:^1.0
```

Requires PHP 8.1+ with `ext-curl` and `ext-json`. The package carries no
`version` key — Packagist reads it from the git tag, and 1.0.0 is the current
release.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```php
use MisarReach\Client;

$client = new Client(getenv('MISARREACH_API_KEY'));
```

The API key is the **first positional argument**, not an options array. The rest
are optional and can be passed by name — `baseUrl`, `maxRetries`, `timeout`.

---

## Quick start

```php
<?php

require 'vendor/autoload.php';

use MisarReach\Client;

// The API key is the first positional argument — not an options array.
$client = new Client(getenv('MISARREACH_API_KEY'));

$job = $client->leads->search([
    'query' => 'CTOs at Series A fintech',
    'useAI' => true,
]);

$snapshot = $client->leads->jobStatus($job['jobId']);
printf("%s %d\n", $snapshot['job']['status'], count($snapshot['results']));
```

The remaining constructor arguments are optional and can be passed by name:

```php
$client = new Client(
    'mrk_your_key',
    'https://reach.misar.io/api',  // base URL; defaults to https://api.misar.io/reach/api
    maxRetries: 5,                 // total attempts per call, default 3
    timeout: 60,                   // per-request timeout in seconds, default 30
);
```

---

## What's in the package

- `MisarReach\Client` — constructed with your API key. Every resource is a
  `public readonly` property assigned in the constructor, so you reach them with
  `->`, not with a method call and not through `__get`:

  ```php
  $client = new Client('mrk_your_key');
  $client->leads;      $client->deals;        $client->pipeline;
  $client->campaigns;  $client->contacts;     $client->conversations;
  $client->channels;   $client->salesAgent;   $client->autopilot;
  $client->plan;       $client->settings;     $client->workspaces;
  $client->webhooks;   $client->notifications; $client->deliverability;
  $client->campaignTemplates; $client->ads;
  ```

- **17 resource classes**, all in the `MisarReach\` namespace and all
  autoloadable by name (PSR-4) so you can type-hint your own helpers against
  them: `LeadsResource`, `DealsResource`, `PipelineResource`,
  `CampaignsResource`, `CampaignTemplatesResource`, `ContactsResource`,
  `ConversationsResource`, `ChannelsResource`, `SalesAgentResource`,
  `AutopilotResource`, `DeliverabilityResource`, `NotificationsResource`,
  `WebhooksResource`, `WorkspacesResource`, `SettingsResource`, `AdsResource`,
  `PlanResource`. Between them they expose **94 public methods**, one per
  operation in `openapi/reach.openapi.json` — the whole API surface, nothing
  missing and nothing invented.
- **No model classes.** Every method takes an associative `array` and returns a
  decoded associative `array`, matching the open-shape API contract. There is no
  DTO layer to keep in sync, and no hydration step to fail on a field the server
  added yesterday — the trade-off is that your IDE cannot complete response keys,
  so read the OpenAPI spec for the shapes.
- **Errors** — `ApiError` (which extends `\RuntimeException`) and the typed
  subclasses below. Every one of them is an `ApiError`, so a single
  `catch (ApiError $e)` is a valid backstop.
- **Transport** — one cURL handle per call, `Authorization: Bearer`, JSON in and
  out. Unlike the TypeScript SDK, this client **does** retry: 429, 500, 502, 503
  and 504 are re-sent with exponential back-off (500 ms, then 1 s, then 2 s …).
  The `$maxRetries` constructor argument is a **total attempt count**, not a
  count of retries on top of the first try — the default of 3 means one call and
  two retries.
- **SSE streaming** for lead-finder job progress, implemented with a cURL write
  callback rather than a generator: you hand `streamJob()` a callable and it is
  invoked once per event, synchronously, until the server closes the stream. The
  server sends *named* events — `progress`, `found`, `complete`, `error`,
  `timeout` — plus a `: keepalive` comment every 20 seconds, which the parser
  discards rather than surfacing. There is no `[DONE]` sentinel; the call simply
  returns when the stream ends. A job that has **already finished** is answered
  with a JSON snapshot rather than a stream, and the SDK synthesises the terminal
  `complete`/`error` event in its place, so a caller that assumed a stream does
  not hang on nothing.

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
| `import()` | Import up to 5000 contacts; `subscribed` requires consent evidence. |
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

`leads->search()` returns a job id, not leads — the search runs asynchronously.

```php
$job = $client->leads->search([
    'query'   => 'heads of ops at logistics startups',
    'useAI'   => true,
    'filters' => ['location' => 'Berlin', 'companySize' => '11-50'],
]);
$jobId = $job['jobId'];
```

### Stream job progress

`streamJob()` blocks and calls your callable once per event. The third argument
is the raw `data:` payload, for when you want the bytes the server actually
sent.

```php
$client->leads->streamJob($jobId, function (string $event, array $data, string $raw): void {
    match ($event) {
        'progress' => printf("working %d\n", $data['total_found'] ?? 0),
        'found'    => printf("hit %s\n", $data['email'] ?? ''),
        'complete' => printf("done, %d found\n", $data['total_found'] ?? 0),
        'error', 'timeout' => printf("%s: %s\n", $event, $data['error'] ?? ''),
        default    => null,
    };
});
```

There is no cancellation token and the stream has **no read timeout**
(`CURLOPT_TIMEOUT` is 0), so a stuck job holds the connection open. Returning a
value from the callable does nothing; to stop early, throw from inside it — the
exception aborts the transfer and propagates out of `streamJob()`.

### List saved leads

```php
$page = $client->leads->list(['page' => 1, 'limit' => 50]);
printf("%d of %d\n", count($page['leads']), $page['total']);
```

### Create a CRM contact and a deal

```php
$client->contacts->create([
    'email'     => 'cto@acme.com',
    'firstName' => 'Dana',
    'status'    => 'subscribed',
    'consent'   => [
        'source'    => 'signup form /pricing',
        'timestamp' => gmdate('c'),
    ],
]);

$created = $client->deals->create([
    'leadEmail' => 'cto@acme.com',
    'leadName'  => 'Dana Reyes',
    'value'     => 12000,
    'currency'  => 'USD',
]);
$dealId = $created['deal']['id'];
```

`POST /deals` echoes back five fields only — `id`, `status`, `stage`,
`lead_email`, `value`. Re-read through `deals->list()` for the complete row.

### Read and move the pipeline

```php
$board = $client->pipeline->get();
printf("%d stages, %d in open pipeline\n",
    count($board['stages']), $board['revenue']['pipeline']);

// Despite the name, this MOVES a deal: it is POST /pipeline, whose only job is
// to reassign a stage. It does not create a pipeline.
$moved = $client->pipeline->create(['dealId' => $dealId, 'newStage' => 'meeting']);
```

`revenue` is computed over every deal in the workspace, ignoring the filters
applied to the board — it is a workspace total, not a summary of what you see.

### Run a campaign

Steps are ordered by array position; the index becomes `step_order` server-side,
so you do not set it yourself.

```php
$campaign = $client->campaigns->create([
    'name'  => 'Q3 fintech outbound',
    'steps' => [
        ['channel' => 'email', 'subject' => 'Quick question', 'body' => 'Hi {{name}} …'],
        ['channel' => 'email', 'delay_hours' => 72, 'body' => 'Following up …'],
    ],
]);

$result = $client->campaigns->enqueue($campaign['id'], [
    'recipients' => [
        ['email' => 'cto@acme.com', 'name' => 'Dana Reyes', 'company' => 'Acme'],
    ],
]);

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
printf("queued=%d skipped=%d warnings=%d\n",
    $result['queued'], $result['skipped'], count($result['warnings'] ?? []));
```

### Check the plan before an expensive run

```php
$plan     = $client->plan->get();
$searches = $plan['usage']['lead_searches'];

if ($searches['remaining'] === null) {
    printf("unlimited lead searches on %s\n", $plan['plan']['name']);
} elseif ($searches['remaining'] === 0) {
    printf("no searches left; upgrade at %s\n", $plan['upgrade']['url']);
}
```

`usage` is keyed by `lead_searches`, `lead_results`, `autopilot_runs`,
`pipeline_deals` and `linkedin_seats`; plan slugs are `free`, `starter`, `pro`
and `scale`.

### Reply into a conversation

```php
$inbox = $client->conversations->list(['limit' => 25]);

$reply = $client->conversations->reply('cto@acme.com', [
    'message' => 'Happy to walk you through it — does Thursday work?',
]);
printf("replied over %s\n", $reply['channel']);
```

The field is `message`, and the channel is not yours to pick: the server routes
the reply over the thread's own channel and tells you which one it used.

---

## Errors

Every non-2xx throws an `ApiError` or one of its subclasses. All extend
`\RuntimeException`, so an uncaught one behaves like any other PHP exception.

| Class | Thrown for |
|-------|-----------|
| `AuthError` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `NotFoundError` | 404 |
| `RateLimitError` | 429 rate limiting; carries `$balance`, `$freeRemaining`, `$upgrade` |
| `UpgradeRequiredError` | a plan cap was hit — see below |
| `NetworkError` | cURL-level failure, or attempts exhausted |
| `ApiError` | any other non-2xx; carries `$status` and `$errorCode` |

The same mapping applies to the SSE stream, so a plan refusal on
`leads->streamJob()` arrives as the same typed error, not a bare exception.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so 402 is left
out of the retry set and surfaces immediately:

```php
use MisarReach\UpgradeRequiredError;

try {
    $client->leads->search(['query' => '…']);
} catch (UpgradeRequiredError $e) {
    // e.g. feature "lead_searches", current 50 of limit 50
    printf("%s: %d/%d\n", $e->feature, $e->current, $e->limit);
    printf("upgrade at %s\n", $e->upgradeUrl); // resolved to an absolute URL
}
```

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments — though on that path the client burns its retries first,
because the retry decision is made on the status code before the body is read.
This is distinct from the 503 `retry: true` the server sends when it could not
*check* the quota — that one is retried, so "we don't know" is never mistaken
for "you're over your limit".

### Reading `remaining`

In `plan->get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Compare with `=== null` before testing for
zero; PHP's loose `==` reads `null` and `0` as the same value and will tell you
an unlimited plan is spent.

---

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel; SMS
and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around. Sends are also
blocked until a CAN-SPAM sender postal address is set via
`settings->setSenderAddress()`.

---

## Links

- **Website** — https://www.misarreach.com
- **App** — https://reach.misar.io
- **Parent** — https://misar.io
- **Documentation** — https://docs.misar.io/reach
- **Source** — https://github.com/Misar-AI/misarreach-sdks
- **Packagist** — https://packagist.org/packages/misarai/misarreach-php

MIT © [Misar AI](https://misar.io)
