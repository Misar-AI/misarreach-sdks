# MisarReach Kotlin SDK

Official Kotlin client for the [MisarReach](https://reach.misar.io) developer API
(`https://api.misar.io/reach/api`), built on coroutines. Full coverage of Lead
Finder, deals & pipeline, multi-channel outreach, autopilot, sales agent,
campaigns, contacts, conversations, workspaces, settings and ads — plus the SSE
lead-job stream exposed as a `Flow`.

- Docs: https://docs.misar.io/reach/api
- Auth: `mrk_` API bearer key · JVM 17+

## Install (Gradle)

```kotlin
dependencies {
    implementation("io.misar:misarreach-kotlin:1.0.0")
}
```

## Usage

```kotlin
import io.misar.reach.MisarReachClient
import kotlinx.coroutines.flow.collect

val client = MisarReachClient("mrk_...")

// Start a lead search
val job = client.leads.search(mapOf("query" to "SaaS founders"))
val jobId = job["jobId"] as String

// Stream job progress over Server-Sent Events
client.leads.stream(jobId).collect { event ->
    println("progress: ${event["progress"]}")
}

// CRM
client.deals.create(mapOf("title" to "Acme renewal", "value" to 5000))

// Channels
val status = client.channels.status()
```

### Configuration

```kotlin
val client = MisarReachClient(
    apiKey = "mrk_...",
    baseUrl = "https://reach.misar.io/api",
    maxRetries = 5,
)
```

Requests retry idempotently on `429/500/502/503/504` with exponential back-off.
Suspend methods take and return `Map<String, Any>`.

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `salesAgent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`.

## Errors

Non-2xx responses throw `MisarReachException` (`status` property; message
extracted from the standard `{ "error": { "message" } }` envelope);
network/retry-exhaustion failures throw `MisarReachNetworkException` (status `0`).

## License

MIT
