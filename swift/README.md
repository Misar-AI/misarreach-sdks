# MisarReach Swift SDK

Official Swift SDK for [MisarReach](https://reach.misar.io) — lead finder
(23 sources), multi-channel outreach, and CRM (deals, pipeline, sales agents).

Authenticates with a `mrk_` API key against `https://api.misar.io/reach/api`.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/misarai/misarreach-swift", from: "1.0.0")
```

Then add `"MisarReach"` to your target dependencies.

## Usage

```swift
import MisarReach

let client = MisarReachClient(apiKey: "mrk_...")

// Start an async lead search
let job = try await client.leads.search(["query": "saas founders", "limit": 25])

// Poll the job
let status = try await client.leads.jobStatus(jobId: job["jobId"] as! String)

// Enrich / verify / score
_ = try await client.leads.enrich(["email": "jane@acme.com"])
_ = try await client.leads.verifyEmails(["emails": ["a@b.com"]])

// CRM
_ = try await client.deals.create(["title": "Acme", "value": 5000])
let pipeline = try await client.pipeline.get()

// Multi-channel outreach
let channels = try await client.channels.status()
_ = try await client.channels.connectSms(["number": "+1..."])
```

### Live lead-search stream (Server-Sent Events)

```swift
try await client.leads.streamJob(jobId: jobId) { event in
    switch event.event {
    case "progress": print("found:", event.data["total_found"] ?? 0)
    case "complete": print("done")
    case "error":    print("error:", event.data["error"] ?? "")
    default:         break
    }
}
```

## Resources

`leads` · `ads` · `autopilot` · `campaigns` · `channels` · `contacts` ·
`conversations` · `deals` · `pipeline` · `salesAgent` · `settings` ·
`workspaces` — full coverage of the MisarReach API.

## Errors

Throws `MisarReachError`:

- `.apiError(status:message:code:)` — non-2xx (401, 403, 404, 4xx, 5xx)
- `.rateLimit(message:balance:freeRemaining:upgrade:)` — HTTP 429
- `.networkError(message:)` — transport failure / retries exhausted

Retryable statuses (429, 500, 502, 503, 504) are retried with exponential
back-off (`maxRetries`, default 3).

## License

MIT
