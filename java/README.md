# MisarReach Java SDK

Official Java client for the [MisarReach](https://misarreach.com) developer API
(`https://api.misar.io/reach/api`). Full coverage of Lead Finder, deals & pipeline,
multi-channel outreach, autopilot, sales agent, campaigns, contacts,
conversations, workspaces, settings and ads — plus the SSE lead-job stream.
Every method has a synchronous and an `*Async` (`CompletableFuture`) variant.

- Docs: https://docs.misar.io/reach/api
- Auth: `mrk_` API bearer key · Java 17+

## Install (Maven)

```xml
<dependency>
    <groupId>io.misar</groupId>
    <artifactId>misarreach-java</artifactId>
    <version>1.0.0</version>
</dependency>
```

## Usage

```java
import io.misar.reach.MisarReachClient;
import java.util.Map;

MisarReachClient client = new MisarReachClient.Builder("mrk_...").build();

// Start a lead search
Map<String, Object> job = client.leads.search(Map.of("query", "SaaS founders"));
String jobId = (String) job.get("jobId");

// Stream job progress over Server-Sent Events (blocking)
client.leads.stream(jobId, event -> System.out.println("progress: " + event.get("progress")));

// CRM
client.deals.create(Map.of("title", "Acme renewal", "value", 5000));

// Async
client.leads.searchAsync(Map.of("query", "CTOs"))
        .thenAccept(res -> System.out.println(res.get("jobId")));
```

### Configuration

```java
MisarReachClient client = new MisarReachClient.Builder("mrk_...")
        .baseUrl("https://api.misar.io/reach/api")
        .maxRetries(5)
        .build();
```

Requests retry idempotently on `429/500/502/503/504` with exponential back-off.
Methods take and return `Map<String, Object>`.

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `salesAgent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`.

## Errors

Non-2xx responses throw `MisarReachException` — `getStatus()` returns the HTTP
status; the message is extracted from the standard
`{ "error": { "message" } }` envelope. Network errors carry status `0`.

## License

MIT
