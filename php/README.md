# MisarReach PHP SDK

Official PHP SDK for [MisarReach](https://misarreach.com) — lead finder
(23 sources), multi-channel outreach, and CRM (deals, pipeline, sales agents).

Authenticates with a `mrk_` API key against `https://api.misar.io/reach/api`.
Requires PHP 8.1+ (`ext-curl`, `ext-json`).

## Install

```bash
composer require misarai/misarreach-php
```

## Usage

```php
use MisarReach\Client;

$client = new Client('mrk_...');

// Start an async lead search
$job = $client->leads->search(['query' => 'saas founders', 'limit' => 25]);

// Poll the job
$status = $client->leads->jobStatus($job['jobId']);

// Enrich / verify / score
$client->leads->enrich(['email' => 'jane@acme.com']);
$client->leads->verifyEmails(['emails' => ['a@b.com']]);

// CRM
$client->deals->create(['title' => 'Acme', 'value' => 5000]);
$pipeline = $client->pipeline->get();

// Multi-channel outreach
$channels = $client->channels->status();
$client->channels->connectSms(['number' => '+1...']);
```

### Live lead-search stream (Server-Sent Events)

```php
$client->leads->streamJob($jobId, function (string $event, array $data, string $raw) {
    match ($event) {
        'progress' => printf("found: %d\n", $data['total_found'] ?? 0),
        'complete' => print("done\n"),
        'error'    => printf("error: %s\n", $data['error'] ?? ''),
        default    => null,
    };
});
```

## Resources

`leads` · `ads` · `autopilot` · `campaigns` · `channels` · `contacts` ·
`conversations` · `deals` · `pipeline` · `salesAgent` · `settings` ·
`workspaces` — full coverage of the MisarReach API.

## Errors

Throws typed `ApiError` subclasses:

- `AuthError` — 401 / 403
- `NotFoundError` — 404
- `RateLimitError` (`$balance`, `$freeRemaining`, `$upgrade`) — 429
- `NetworkError` — transport failure / retries exhausted
- `ApiError` — any other non-2xx (`$status`, `$code`)

Retryable statuses (429, 500, 502, 503, 504) are retried with exponential
back-off (`$maxRetries`, default 3).

## License

MIT
