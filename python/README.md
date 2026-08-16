# MisarReach Python SDK

Official Python SDK for the [MisarReach](https://reach.misar.io) Developer API —
lead finder (23 sources), multi-channel outreach, deals/pipeline CRM, autopilot,
and the AI sales agent.

Full reference: [`docs.misar.io/reach`](https://docs.misar.io/reach) · OpenAPI: `openapi/reach.openapi.json`.

## Install

```bash
pip install misar-reach
```

## Auth

Use a reach developer key (`mrk_…`). It is validated only against the reach-owned
key table, so a key from any other Misar product is rejected. Sent as
`Authorization: Bearer mrk_…`.

## Quick start

```python
from misar_reach import MisarReachClient

client = MisarReachClient("mrk_your_key")

# Start an async lead search, then poll or stream the job
job = client.leads.search({"query": "SaaS founders in Berlin", "useAI": True})
for evt in client.leads.stream_job(job["jobId"]):
    print(evt.event, evt.data)          # progress … then complete / error

leads = client.leads.list(page=1, limit=50)

# CRM
deal = client.deals.create({"leadEmail": "cto@acme.com", "value": 5000})
board = client.pipeline.get()
client.pipeline.move({"dealId": deal["id"], "stage": "interested"})

# Channels
client.channels.status()
client.channels.connect("whatsapp", {"phoneNumberId": "…", "accessToken": "…"})
```

### Async

Every method has an `a`-prefixed async twin:

```python
import asyncio
from misar_reach import MisarReachClient

async def main():
    client = MisarReachClient("mrk_your_key")
    res = await client.leads.asearch({"query": "fintech CFOs"})
    async for evt in client.leads.astream_job(res["jobId"]):
        print(evt.event, evt.data)

asyncio.run(main())
```

## Resources

| Accessor | Coverage |
|----------|----------|
| `client.leads` | search · discover · enrich · verify · score · list · export · job status + **SSE stream** · feedback · recommendations · preview_message · send_to_campaign · add_to_segment · companies · lists · saved_searches · scoring_rules · account · config |
| `client.deals` | list · create · update · delete · activity · suggestions |
| `client.pipeline` | get board · move deal stage |
| `client.channels` | status · update_status · opt_in_links · connect(whatsapp/sms/telegram/twitter/instagram/facebook/discord) · push_subscribe / push_unsubscribe |
| `client.autopilot` | start · runs · get · status · set_status |
| `client.sales_agent` | config · update_config · actions · conversations · process |
| `client.campaigns` | list · create · get · update · delete · enqueue |
| `client.contacts` | list · create · get · update · delete · bulk · import · segments · stats |
| `client.conversations` | list · get(email) |
| `client.settings` | sender_address · set_sender_address |
| `client.workspaces` | list · create · members · add_member · remove_member |
| `client.ads` | linkedin_company_audience |

## Errors

All non-2xx responses raise a subclass of `ReachError`:

- `ReachAuthError` (401/403)
- `ReachNotFoundError` (404)
- `ReachRateLimitError` (429) — carries `retry_after`
- `ReachUpgradeRequiredError` (429 with `upgrade: true`)
- `ReachAPIError` (any other non-2xx) — carries `status`, `code`, `error`
- `ReachNetworkError` (transport failure)

Retries with exponential backoff are automatic for 429/5xx (configurable via
`max_retries`).

## License

MIT
