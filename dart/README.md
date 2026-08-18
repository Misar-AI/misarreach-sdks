# MisarReach Dart SDK

Official Dart client for the [MisarReach](https://misarreach.com) developer API —
lead finder (23 sources), multi-channel outreach, CRM (deals + pipeline),
autopilot, and the AI sales agent.

- Base URL: `https://api.misar.io/reach/api`
- Auth: `Authorization: Bearer mrk_...` (reach-only developer key)
- Automatic retries with backoff on `429/5xx` (honours `Retry-After`)
- Typed error classes + `Stream<ReachSseEvent>` for lead-finder job progress

## Install

```yaml
# pubspec.yaml
dependencies:
  misar_reach: ^1.0.0
```

## Usage

```dart
import 'package:misar_reach/misar_reach.dart';

final reach = MisarReachClient(apiKey: 'mrk_...');

// Lead Finder
final job = await reach.leads.search({'query': 'Series A SaaS founders'});
await reach.leads.enrich({'email': 'jane@acme.com'});
await reach.leads.score({'leadIds': ['l_1', 'l_2']});

// Live progress (Server-Sent Events)
await for (final evt in reach.leads.streamJob(job['jobId'] as String)) {
  print('${evt.event}: ${evt.data}');
}

// CRM
final deal = await reach.deals.create({'title': 'Acme', 'value': 12000});
await reach.pipeline.get();
await reach.deals.suggestions(deal['id'] as String);

// Channels + autopilot
await reach.channels.connectWhatsapp({'token': '...'});
await reach.autopilot.start({'campaignId': 'camp_1'});

reach.close();
```

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `salesAgent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`

## Errors

`AuthError` (401/403) · `NotFoundError` (404) · `RateLimitError` (429, with
`retryAfter`/`balance`/`freeRemaining`) · `UpgradeRequiredError` (429 upgrade) ·
`MisarReachError` (base, with `status`/`code`/`body`) ·
`MisarReachNetworkError` (connectivity).

## Test

```bash
dart pub get
dart test
```

See https://docs.misar.io/reach/api for the full reference.
