# MisarReach Flutter SDK

Official Flutter client for the [MisarReach](https://misarreach.com) developer
API — lead finder (23 sources), multi-channel outreach, CRM (deals + pipeline),
autopilot, and the AI sales agent. For iOS, Android, macOS, and Web.

- Base URL: `https://api.misar.io/reach/api`
- Auth: `Authorization: Bearer mrk_...` (reach-only developer key)
- Secure on-device key storage via `flutter_secure_storage`
- Automatic retries with backoff on `429/5xx` (honours `Retry-After`)
- Typed exceptions + `Stream<ReachSseEvent>` for lead-finder job progress

## Install

```yaml
# pubspec.yaml
dependencies:
  misar_reach_flutter: ^5.0.0
```

## Usage

```dart
import 'package:misar_reach_flutter/misar_reach_flutter.dart';

// Direct key
final reach = MisarReachClient(apiKey: 'mrk_...');

// Or load from the secure keystore (preferred on mobile)
await MisarReachClient.saveApiKey('mrk_...');
final reach = await MisarReachClient.withSecureStorage();

// Lead Finder
final job = await reach.leads.search({'query': 'Series A SaaS founders'});
await reach.leads.enrich({'email': 'jane@acme.com'});

// Live progress (Server-Sent Events)
await for (final evt in reach.leads.streamJob(job['jobId'] as String)) {
  debugPrint('${evt.event}: ${evt.data}');
}

// CRM + channels + autopilot
await reach.deals.create({'title': 'Acme', 'value': 12000});
await reach.pipeline.get();
await reach.channels.connectWhatsapp({'token': '...'});
await reach.autopilot.start({'campaignId': 'camp_1'});

reach.close();
```

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `salesAgent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`

## Errors

`MisarReachAuthException` (401/403) · `MisarReachNotFoundException` (404) ·
`MisarReachRateLimitException` (429, with `retryAfter`/`balance`/`freeRemaining`) ·
`MisarReachUpgradeRequiredException` (429 upgrade) · `MisarReachException` (base) ·
`MisarReachNetworkException` (connectivity).

## Test

```bash
flutter pub get
dart run build_runner build   # generates client_test.mocks.dart
flutter test
```

See https://docs.misar.io/reach/api for the full reference.
