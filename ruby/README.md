# MisarReach Ruby SDK

Official Ruby client for the [MisarReach](https://reach.misar.io) developer API —
lead finder (23 sources), multi-channel outreach, CRM (deals + pipeline),
autopilot, and the AI sales agent.

- Base URL: `https://api.misar.io/reach/api`
- Auth: `Authorization: Bearer mrk_...` (reach-only developer key)
- Pure `Net::HTTP` — no runtime dependencies
- Automatic retries with backoff on `429/5xx` (honours `Retry-After`)
- Typed error classes + Server-Sent Events streaming for lead-finder jobs

## Install

```ruby
# Gemfile
gem "misarreach"
```

```bash
gem build misar_reach.gemspec
```

## Usage

```ruby
require "misar_reach"

reach = MisarReach.new(api_key: ENV["MISARREACH_API_KEY"]) # mrk_...

# Lead Finder
job = reach.leads.search(query: "Series A SaaS founders", location: "US")
status = reach.leads.job(job["jobId"])
reach.leads.enrich(email: "jane@acme.com")
reach.leads.verify(emails: ["jane@acme.com"])
reach.leads.score(leadIds: ["l_1", "l_2"])

# Live progress via Server-Sent Events
reach.leads.stream_job(job["jobId"]) do |evt|
  puts "#{evt[:event]}: #{evt[:data].inspect}"
end

# CRM
deal = reach.deals.create(title: "Acme expansion", value: 12_000, stage: "qualified")
reach.pipeline.get
reach.deals.suggestions(deal["id"])

# Channels
reach.channels.status
reach.channels.connect_whatsapp(phoneNumberId: "...", token: "...")

# Autopilot & sales agent
reach.autopilot.start(campaignId: "camp_1")
reach.sales_agent.process(conversationId: "conv_1")
```

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `sales_agent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`

## Errors

| Class | When |
|-------|------|
| `MisarReach::AuthError` | 401 / 403 — missing or wrong-scope key |
| `MisarReach::NotFoundError` | 404 |
| `MisarReach::RateLimitError` | 429 (`retry_after`, `balance`, `free_remaining`) |
| `MisarReach::UpgradeRequiredError` | 429 with `upgrade: true` |
| `MisarReach::ApiError` | any other non-2xx (`status`, `code`, `body`) |
| `MisarReach::NetworkError` | connectivity failure |

## Test

```bash
bundle install
bundle exec rspec
```

See https://docs.misar.io/reach/api for the full reference.
