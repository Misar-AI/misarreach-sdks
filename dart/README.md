# MisarReach Dart SDK

> Dart client for MisarReach — find leads, enrich and verify them, then work them through a CRM pipeline and multi-channel outreach.

[![pub package](https://img.shields.io/pub/v/misarreach.svg)](https://pub.dev/packages/misarreach)
[![pub points](https://img.shields.io/pub/points/misarreach)](https://pub.dev/packages/misarreach/score)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**17 resource groups · 94 operations**

Works on Dart 3, on native platforms — the client imports `dart:io`, so it suits
server-side Dart, CLI tools and native app targets rather than the web. Maps in,
maps out. Talks to `https://api.misar.io/reach/api`.

---

## Install

```bash
dart pub add misarreach
```

Or add it by hand:

```yaml
# pubspec.yaml
dependencies:
  misarreach: ^5.0.2
```

Requires Dart `>=3.0.0 <4.0.0` and pulls in `http: ^1.2.0`. The client imports
`dart:io`, so it targets native platforms — it is not web-compatible.

---

## Authentication

Create a key in **Settings → API keys** in the MisarReach app. Reach keys start
with `mrk_` and are validated against the reach-owned key table only, so a key
from another Misar product is rejected. It travels as
`Authorization: Bearer mrk_…`.

```dart
import 'package:misarreach/misarreach.dart';

final reach = MisarReachClient(apiKey: Platform.environment['MISARREACH_API_KEY']!);
```

`apiKey:` is a required named argument. `baseUrl:`, `maxRetries:` and `timeout:`
are optional. Call `reach.close()` when you are done — the client holds an
`http.Client` that keeps the isolate alive until it is released.

---

## Quick start

```dart
import 'package:misarreach/misarreach.dart';

Future<void> main() async {
  final reach = MisarReachClient(apiKey: 'mrk_your_key');

  final job = await reach.leads.search({
    'query': 'CTOs at Series A fintech',
    'useAI': true,
  });

  final snapshot = await reach.leads.job(job['jobId'] as String);
  final results = snapshot['results'] as List<dynamic>;
  print('${(snapshot['job'] as Map)['status']} — ${results.length} leads');

  reach.close();
}
```
---

## What's in the package

- `MisarReachClient` — constructed with a **named** `apiKey` argument. Resources
  are plain fields on the instance: `reach.leads`, `reach.deals`, `reach.plan`, …

  ```dart
  MisarReachClient({
    required String apiKey,
    String baseUrl = 'https://api.misar.io/reach/api',
    int maxRetries = 3,
    http.Client? httpClient,
  })
  ```

  Call `reach.close()` when you are done to release the underlying
  `http.Client` — a long-lived process that never closes it leaks a connection
  pool.
- **17 resource classes**, all exported by name so you can type your own helpers
  against them: `LeadsResource`, `DealsResource`, `PipelineResource`,
  `ChannelsResource`, `AutopilotResource`, `SalesAgentResource`,
  `CampaignsResource`, `ContactsResource`, `ConversationsResource`,
  `CampaignTemplatesResource`, `DeliverabilityResource`,
  `NotificationsResource`, `WebhooksResource`, `WorkspacesResource`,
  `SettingsResource`, `AdsResource`, `PlanResource`. Between them they expose
  **94 methods, one per API operation** — the full 70-path / 94-operation
  surface of `openapi/reach.openapi.json`.
- **No generated model classes.** Every call returns
  `Future<Map<String, dynamic>>` and takes `Map<String, dynamic>` where a body
  is required, matching the open-shape API contract. Read fields with a cast:
  `job['jobId'] as String`. A 2xx with an empty body decodes to `{}`, and a
  top-level JSON array is wrapped as `{'data': [...]}`. `ReachSseEvent` is the
  one typed shape in the package.
- **Errors** — `MisarReachError` and the typed subclasses below. All implement
  `Exception`.
- **Transport** — `package:http` with a `Bearer` header, and it **does retry**:
  429, 500, 502, 503 and 504 are retried up to `maxRetries` attempts (default 3,
  so two retries), honouring a `Retry-After` header when the server sends one
  and otherwise backing off 300 ms · 2ⁿ. A dropped connection
  (`http.ClientException`) is retried on the same schedule. A **402 plan refusal
  is never retried**, because retrying cannot help. Note that a *429* carrying
  `upgrade: true` is currently retried before it surfaces as
  `UpgradeRequiredError` — the outcome is correct, but it costs the back-off
  delay first.
- **SSE streaming** for lead-finder job progress, as a plain Dart
  `Stream<ReachSseEvent>`. The server sends *named* events — `progress`,
  `found`, `complete`, `error`, `timeout` — plus a `: keepalive` comment every
  20 seconds, which the parser skips. There is no `[DONE]` sentinel; the stream
  simply ends when the server closes it. A job that has **already finished** is
  answered with a JSON snapshot rather than a stream, and the SDK synthesises
  the terminal `complete`/`error` frame from it, so a caller that assumed a
  stream does not hang on nothing.

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
| `search()` | Start an async search across 23 sources — returns a `jobId`, not leads. |
| `discover()` | Company and lead discovery by firmographic filters. |
| `enrich()` | Enrich a saved lead from external data (spends credits). |
| `verify()` | Verify email deliverability for one address or a batch (spends credits). |
| `score()` | AI-score leads by job id or an explicit lead-id list. |
| `export()` | Export saved leads as CSV or JSON. |
| `searchHistory()` | Past searches with their result counts. |
| `recommendations()` | Suggested next leads based on what you have already saved. |
| `previewMessage()` | Draft the AI outreach message for a lead without sending it. |
| `sendToCampaign()` | Push selected leads into an existing campaign. |
| `addToSegment()` | Add selected leads to a contact segment. |
| `company()` | Company profile for a domain. |
| `companyPeople()` | People found at that company. |
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
| `job()` | Poll a search job for status and the results so far. |
| `jobFeedback()` | Rate a job's results so scoring improves. |
| `streamJob()` | SSE progress for a running job — named events, no `[DONE]` sentinel. |

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
| `update()` | Move a deal to another stage. |

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

`leads.search()` returns a job id, not leads — the search runs asynchronously
and answers `202`.

```dart
final job = await reach.leads.search({
  'query': 'heads of ops at logistics startups',
  'useAI': true,
  'filters': {'location': 'Berlin', 'companySize': '11-50'},
});
final jobId = job['jobId'] as String;
```

### Stream job progress

```dart
await for (final evt in reach.leads.streamJob(jobId)) {
  switch (evt.event) {
    case 'progress':
      print('working ${evt.data}');
    case 'found':
      print('hit ${evt.data}');
    case 'complete':
    case 'error':
    case 'timeout':
      print('${evt.event} ${evt.data}');
  }
}
```

`await for` cancels the subscription when you `break`, which closes the
connection — without that, a stuck job holds it open until the server's own
15-minute ceiling.

### List saved leads

```dart
final page = await reach.leads.list(params: {'page': 1, 'limit': 50});
print('${page['total']} saved leads');
```

### Create a CRM contact and a deal

```dart
await reach.contacts.create({
  'email': 'cto@acme.com',
  'firstName': 'Dana',
  'status': 'subscribed',
  'consent': {
    'source': 'signup form /pricing',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  },
});

// `leadEmail` is the only required field on a deal.
final created = await reach.deals.create({
  'leadEmail': 'cto@acme.com',
  'leadName': 'Dana Reyes',
  'value': 12000,
  'currency': 'USD',
});
final dealId = (created['deal'] as Map)['id'] as String;
```

### Read and move the pipeline

```dart
final board = await reach.pipeline.get();
print('${board['revenue']} across stages ${board['stages']}');

// A stage move is a POST to the same pipeline route.
await reach.pipeline.update({'dealId': dealId, 'newStage': 'meeting'});
```

### Run a campaign

```dart
// Steps are flat: the server assigns `step_order` from the array position and
// builds the template from `subject`/`body`.
final campaign = await reach.campaigns.create({
  'name': 'Q3 fintech outbound',
  'steps': [
    {'channel': 'email', 'subject': 'Quick question', 'body': 'Hi {{name}} …'},
    {'channel': 'email', 'delay_hours': 72, 'body': 'Following up …'},
  ],
});

final result = await reach.campaigns.enqueue(campaign['id'] as String, {
  'recipients': [
    {'email': 'cto@acme.com', 'name': 'Dana Reyes', 'company': 'Acme'},
  ],
});

// Check `warnings`: a step whose channel has no inbound path in this deployment
// can never deliver, and the server reports that here rather than silently
// dropping every recipient at dispatch time.
print('${result['queued']} queued, ${result['skipped']} skipped, '
    '${result['warnings']}');
```

### Check the plan before an expensive run

```dart
final plan = await reach.plan.get();
final usage = plan['usage'] as Map<String, dynamic>;
final searches = usage['lead_searches'] as Map<String, dynamic>;

if (searches['remaining'] == null) {
  print('unlimited lead searches on ${(plan['plan'] as Map)['name']}');
} else if (searches['remaining'] == 0) {
  print('no searches left; upgrade at ${(plan['upgrade'] as Map)['url']}');
} else {
  print('${searches['remaining']} lead searches left');
}
```

### Reply into a conversation

```dart
final inbox = await reach.conversations.list(params: {'limit': 25});
print('${(inbox['conversations'] as List).length} threads');

// The field is `message`, and the channel is chosen server-side from the
// thread — you do not pass one.
await reach.conversations.reply('cto@acme.com', {
  'message': 'Happy to walk you through it — does Thursday work?',
});
```

---

## Errors

Every non-2xx throws a `MisarReachError` or one of its subclasses.

| Class | Thrown for |
|-------|-----------|
| `AuthError` | 401 and 403 — missing, invalid or out-of-scope `mrk_` key |
| `NotFoundError` | 404 |
| `RateLimitError` | 429 rate limiting; carries `retryAfter`, `balance`, `freeRemaining` |
| `UpgradeRequiredError` | a plan cap was hit — see below |
| `MisarReachNetworkError` | connectivity failure; `status` is `0` |
| `MisarReachError` | any other non-2xx; carries `status`, `code` and the decoded `body` |

Order your `on` clauses subclass-first — `on MisarReachError` catches every one
of them.

The same mapping applies to the SSE stream, so a plan refusal on
`leads.streamJob()` arrives as the same typed error, not a bare exception.

### The 402 upgrade case

A counted plan cap answers **402** with `upgrade: true` — not 403, and not 429.
Retrying cannot help until the cap resets or the plan changes, so the retry loop
skips it and the error surfaces immediately:

```dart
try {
  await reach.leads.discover({'domain': 'acme.com'});
} on UpgradeRequiredError catch (err) {
  // e.g. feature "lead_searches", current 50 of limit 50
  print('${err.feature}: ${err.current}/${err.limit}');
  print('upgrade at ${err.upgradeUrl}'); // resolved to an absolute URL
}
```

`upgradeUrl` resolves the app-relative path the server sends against
`https://misarreach.com`, so it is always absolute.

429 is still accepted as an upgrade refusal when `upgrade: true` is present, for
older deployments. This is distinct from the 503 `retry: true` the server sends
when it could not *check* the quota — that one is retried, so "we don't know" is
never mistaken for "you're over your limit".

### Reading `remaining`

In `plan.get()`, a `usage` entry's `limit` is `null` when the plan is unlimited
for that counter, and `remaining` is `null` alongside it — deliberately **not**
`0`, which would read as exhausted. Test for `null` before comparing.

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
- **pub.dev** — https://pub.dev/packages/misarreach

MIT © [Misar AI](https://misar.io)
