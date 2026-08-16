# MisarReach SDKs

Official client libraries for the [MisarReach](https://reach.misar.io) API —
lead finder, multi-channel outreach, deals/pipeline CRM, autopilot and the AI
sales agent.

Every SDK covers the full public API surface: all 69 documented endpoints plus
the SSE stream for lead-finder job progress. They speak only HTTPS and
server-sent events, and authenticate with a MisarReach developer key
(`mrk_…`) — create one at
[reach.misar.io/settings/api-keys](https://reach.misar.io/settings/api-keys).

## Install

| Language | Registry | Package |
|---|---|---|
| TypeScript / JavaScript | npm | `@misarreach/sdk` |
| Python | PyPI | `misar-reach` |
| Rust | crates.io | `misarreach` |
| Ruby | RubyGems | `misarreach` |
| PHP | Packagist | `misarai/misarreach-php` |
| Dart | pub.dev | `misar_reach` |
| Flutter | pub.dev | `misar_reach_flutter` |
| C# / .NET | NuGet | `Misar.Reach` |
| Java | Maven Central | `io.misar:misarreach-java` |
| Kotlin | Maven Central | `io.misar:misarreach-kotlin` |
| Go | module proxy | `github.com/Misar-AI/misarreach-sdks/go` |
| Swift | Swift PM | `https://github.com/Misar-AI/misarreach-sdks` |

Each language directory has its own README with usage for that SDK.

## Quick start

```ts
import { MisarReachClient } from "@misarreach/sdk";

const reach = new MisarReachClient({ apiKey: process.env.MISAR_REACH_API_KEY! });

const results = await reach.leadFinder.search({
  query: "SaaS founders in Berlin",
  useAI: true,
});

for await (const event of reach.leadFinder.stream(results.jobId)) {
  console.log(event.event, event.data);
}
```

## Plan limits

Quotas are enforced server-side against the subscription that owns the API key,
not in the client. A request beyond your plan's allowance returns `402` with the
limit that was hit; a `503` with `"retry": true` means the quota could not be
verified and the request was refused rather than allowed through. Rates and
credits are documented at [reach.misar.io/docs](https://reach.misar.io/docs).

## Releases

Versions are per-SDK. A bump to a language's manifest on `main` is tagged
`<language>/vX.Y.Z` automatically, and that tag publishes to the registry.
Go and Swift have no upload step — for them the git tag *is* the release, which
is why `Package.swift` sits at the repository root and the Go module path
carries the `/go` suffix.

## Licence

MIT. See [LICENSE](LICENSE).
