# @misarreach/sdk

TypeScript SDK for the [MisarReach](https://reach.misar.io) API.

MisarReach is a multi-channel outreach platform: a 23-source lead finder,
campaign dispatch across email and social channels, a deals/pipeline CRM,
autopilot, and an AI sales agent.

## Install

```bash
npm install @misarreach/sdk
```

## Usage

```ts
import { MisarReachClient } from "@misarreach/sdk";

const reach = new MisarReachClient({ apiKey: process.env.MISAR_REACH_API_KEY! });

const { leads } = await reach.leads.search({ query: "CTOs at Series A fintech" });
const deal = await reach.deals.create({ leadEmail: leads[0].email, value: 5000 });
```

Create an API key in **Settings → API keys**. Keys are scoped; grant only the
scopes the integration needs.

## Compliance

Outreach is not uniformly permitted. Email is the only cold-capable channel;
SMS and WhatsApp require a consent record, and several social channels may only
reply inside a window the recipient opened. The API enforces this server-side
and will refuse a send rather than let you breach TCPA, CASL or GDPR — a refusal
is the SDK working correctly, not an error to retry around.

## Documentation

- API reference: <https://docs.misar.io/reach/>
- OpenAPI spec: `openapi/reach.openapi.json` in the repository

## License

MIT — see [LICENSE](./LICENSE).
