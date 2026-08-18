# MisarReach Rust SDK

Official async Rust client for the [MisarReach](https://misarreach.com) developer
API (`https://api.misar.io/reach/api`). Full coverage of Lead Finder, deals &
pipeline, multi-channel outreach, autopilot, sales agent, campaigns, contacts,
conversations, workspaces, settings and ads — plus the SSE lead-job stream.

- Docs: https://docs.misar.io/reach/api
- Auth: `mrk_` API bearer key

## Install

```toml
[dependencies]
misarreach = "1"
tokio = { version = "1", features = ["full"] }
serde_json = "1"
```

## Usage

```rust
use serde_json::json;

#[tokio::main]
async fn main() -> Result<(), misarreach::ReachError> {
    let client = misarreach::MisarReachClient::new("mrk_...");

    // Start a lead search
    let job = client.leads.search(json!({ "query": "SaaS founders in Berlin" })).await?;
    let job_id = job["jobId"].as_str().unwrap().to_string();

    // Stream job progress over Server-Sent Events
    client.leads.stream(&job_id, |event| {
        println!("progress: {}", event["progress"]);
    }).await?;

    // CRM
    client.deals.create(json!({ "title": "Acme renewal", "value": 5000 })).await?;

    // Channels
    let status = client.channels.status().await?;
    println!("{status}");
    Ok(())
}
```

### Configuration

```rust
let client = misarreach::MisarReachClient::new("mrk_...")
    .with_base_url("https://api.misar.io/reach/api")
    .with_max_retries(5);
```

Requests retry idempotently on `429/500/502/503/504` with exponential back-off.
Every method takes and returns `serde_json::Value`; optional typed models live in
the `types` module.

## Resources

`leads` · `deals` · `pipeline` · `channels` · `autopilot` · `sales_agent` ·
`campaigns` · `contacts` · `conversations` · `workspaces` · `settings` · `ads`.

## Errors

All failures surface as `ReachError` — `Api { status, message }` (message
extracted from the standard `{ "error": { "message" } }` envelope), `Network`, or
`Json`.

## License

MIT
