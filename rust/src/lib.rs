//! Official Rust SDK for the **MisarReach** developer API
//! (`https://api.misar.io/reach/api`).
//!
//! Authenticate with an `mrk_` API key. Every resource method is async and
//! retries idempotently on transient statuses (429, 500, 502, 503, 504) with
//! exponential back-off.
//!
//! ```no_run
//! # async fn demo() -> Result<(), misarreach::ReachError> {
//! use serde_json::json;
//! let client = misarreach::MisarReachClient::new("mrk_...");
//! let job = client.leads.search(json!({ "query": "SaaS founders in Berlin" })).await?;
//! # Ok(()) }
//! ```

pub mod errors;
pub mod types;

use std::sync::Arc;
use std::time::Duration;

use reqwest::{Client as HttpClient, Method};
use serde_json::Value;
use tokio::time::sleep;

pub use errors::ReachError;

// ── Constants ─────────────────────────────────────────────────────────────────

const DEFAULT_BASE_URL: &str = "https://api.misar.io/reach/api";
const DEFAULT_MAX_RETRIES: u32 = 3;
const RETRY_BASE_MS: u64 = 200;
/// Resolves the app-relative `upgrade_url` the server returns.
const APP_ORIGIN: &str = "https://misarreach.com";

static RETRYABLE: &[u16] = &[429, 500, 502, 503, 504];

// ── Inner ─────────────────────────────────────────────────────────────────────

struct Inner {
    api_key: String,
    base_url: String,
    http: HttpClient,
    max_retries: u32,
}

impl Inner {
    fn new(api_key: &str, base_url: &str, max_retries: u32) -> Self {
        Self {
            api_key: api_key.to_owned(),
            base_url: base_url.trim_end_matches('/').to_owned(),
            http: HttpClient::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .expect("failed to build HTTP client"),
            max_retries,
        }
    }

    /// Returns an `UpgradeRequired` when the body is a plan refusal.
    ///
    /// The server sends `upgrade_url` app-relative (`/settings?tab=billing`);
    /// it is resolved against the app origin so callers can link to it.
    fn parse_upgrade_required(status: u16, text: &str) -> Option<ReachError> {
        if !(status == 402 || status == 429) {
            return None;
        }
        let v: Value = serde_json::from_str(text).ok()?;
        if v.get("upgrade") != Some(&Value::Bool(true)) {
            return None;
        }

        let upgrade_url = v.get("upgrade_url").and_then(Value::as_str).map(|u| {
            if u.starts_with("http://") || u.starts_with("https://") {
                u.to_owned()
            } else if u.starts_with('/') {
                format!("{APP_ORIGIN}{u}")
            } else {
                format!("{APP_ORIGIN}/{u}")
            }
        });

        Some(ReachError::UpgradeRequired {
            status,
            message: Self::extract_message(text),
            feature: v.get("feature").and_then(Value::as_str).map(str::to_owned),
            limit: v.get("limit").and_then(Value::as_i64),
            current: v.get("current").and_then(Value::as_i64),
            upgrade_url,
        })
    }

    fn extract_message(text: &str) -> String {
        serde_json::from_str::<Value>(text)
            .ok()
            .and_then(|v| {
                // standard envelope: { "error": { "message": "..." } }
                v.get("error")
                    .and_then(|e| e.get("message"))
                    .and_then(|m| m.as_str())
                    .map(str::to_owned)
                    // or a bare string message/error
                    .or_else(|| {
                        v.get("message")
                            .or_else(|| v.get("error"))
                            .and_then(|m| m.as_str())
                            .map(str::to_owned)
                    })
            })
            .unwrap_or_else(|| text.to_owned())
    }

    async fn request(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, ReachError> {
        let url = format!("{}{}", self.base_url, path);
        let mut last_err: Option<ReachError> = None;

        for attempt in 0..self.max_retries {
            if attempt > 0 {
                sleep(Duration::from_millis(RETRY_BASE_MS * (1 << (attempt - 1)))).await;
            }

            let mut req = self
                .http
                .request(method.clone(), &url)
                .header("Authorization", format!("Bearer {}", self.api_key))
                .header("Content-Type", "application/json");

            if let Some(ref b) = body {
                req = req.json(b);
            }

            match req.send().await {
                Err(e) => {
                    last_err = Some(ReachError::Network(e));
                }
                Ok(resp) => {
                    let status = resp.status();
                    let status_u16 = status.as_u16();

                    if status_u16 == 204 {
                        return Ok(Value::Null);
                    }

                    let text = resp.text().await.unwrap_or_default();

                    // A 429 rate limit and a 429 plan refusal are identical by
                    // status; only the first is worth retrying. The server's
                    // 503 `retry: true` carries no `upgrade`, so "we could not
                    // check the quota" still retries.
                    if let Some(err) = Self::parse_upgrade_required(status_u16, &text) {
                        return Err(err);
                    }

                    if RETRYABLE.contains(&status_u16) && attempt < self.max_retries - 1 {
                        last_err = Some(ReachError::Api {
                            status: status_u16,
                            message: status.to_string(),
                        });
                        continue;
                    }

                    if !status.is_success() {
                        return Err(ReachError::Api {
                            status: status_u16,
                            message: Self::extract_message(&text),
                        });
                    }

                    if text.trim().is_empty() {
                        return Ok(Value::Null);
                    }
                    return serde_json::from_str(&text).map_err(ReachError::Json);
                }
            }
        }

        Err(last_err.unwrap_or(ReachError::Api {
            status: 0,
            message: "max retries exceeded".to_owned(),
        }))
    }

    async fn get_with_params(&self, path: &str, params: Value) -> Result<Value, ReachError> {
        let url = format!("{}{}", self.base_url, path);

        let query_pairs: Vec<(String, String)> = if let Some(obj) = params.as_object() {
            obj.iter()
                .filter_map(|(k, v)| {
                    let val = match v {
                        Value::String(s) => Some(s.clone()),
                        Value::Number(n) => Some(n.to_string()),
                        Value::Bool(b) => Some(b.to_string()),
                        _ => None,
                    };
                    val.map(|v| (k.clone(), v))
                })
                .collect()
        } else {
            vec![]
        };

        let mut last_err: Option<ReachError> = None;

        for attempt in 0..self.max_retries {
            if attempt > 0 {
                sleep(Duration::from_millis(RETRY_BASE_MS * (1 << (attempt - 1)))).await;
            }

            let req = self
                .http
                .get(&url)
                .header("Authorization", format!("Bearer {}", self.api_key))
                .query(&query_pairs);

            match req.send().await {
                Err(e) => {
                    last_err = Some(ReachError::Network(e));
                }
                Ok(resp) => {
                    let status = resp.status();
                    let status_u16 = status.as_u16();

                    if RETRYABLE.contains(&status_u16) && attempt < self.max_retries - 1 {
                        last_err = Some(ReachError::Api {
                            status: status_u16,
                            message: status.to_string(),
                        });
                        continue;
                    }

                    if status_u16 == 204 {
                        return Ok(Value::Null);
                    }

                    let text = resp.text().await.unwrap_or_default();

                    // Reads are refused by the same 402 `upgrade: true` envelope
                    // as writes; without this a plan refusal on any GET route
                    // arrived as a bare `Api { status: 402 }` and lost `feature`,
                    // `limit`, `current` and `upgrade_url`.
                    if let Some(err) = Self::parse_upgrade_required(status_u16, &text) {
                        return Err(err);
                    }

                    if !status.is_success() {
                        return Err(ReachError::Api {
                            status: status_u16,
                            message: Self::extract_message(&text),
                        });
                    }

                    if text.trim().is_empty() {
                        return Ok(Value::Null);
                    }
                    return serde_json::from_str(&text).map_err(ReachError::Json);
                }
            }
        }

        Err(last_err.unwrap_or(ReachError::Api {
            status: 0,
            message: "max retries exceeded".to_owned(),
        }))
    }

    /// Opens the SSE stream and invokes `on_event` for each frame.
    ///
    /// MisarReach names its events — `progress`, `found`, `complete`, `error`
    /// and `timeout` — so the name is carried through rather than discarded;
    /// without it a caller cannot tell completion from progress. Frames end at
    /// a blank line and may span several `data:` lines, and `: keepalive`
    /// comments (sent every 20s) are skipped.
    ///
    /// Deliberately not retried: replaying a stream that failed mid-flight
    /// would duplicate whatever the caller already consumed.
    async fn sse<F>(&self, path: &str, mut on_event: F) -> Result<(), ReachError>
    where
        F: FnMut(ReachSseEvent),
    {
        use futures_util::StreamExt;

        let url = format!("{}{}", self.base_url, path);
        let resp = self
            .http
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Accept", "text/event-stream")
            .send()
            .await?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            if let Some(err) = Self::parse_upgrade_required(status.as_u16(), &text) {
                return Err(err);
            }
            return Err(ReachError::Api {
                status: status.as_u16(),
                message: Self::extract_message(&text),
            });
        }

        // The route does not always stream. A job that has already finished is
        // answered with a JSON snapshot, because there is nothing left to
        // stream. Parsing that as SSE finds no frames and returns silently, so
        // the caller would see nothing rather than the outcome. Synthesise the
        // terminal frame the SSE path would have sent.
        let is_stream = resp
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|ct| ct.contains("text/event-stream"));

        if !is_stream {
            let text = resp.text().await.unwrap_or_default();
            let data = serde_json::from_str::<Value>(&text)
                .unwrap_or_else(|_| Value::String(text.clone()));
            let event = if data.get("status").and_then(Value::as_str) == Some("failed") {
                "error"
            } else {
                "complete"
            };
            on_event(ReachSseEvent {
                event: event.to_owned(),
                data,
                raw: text,
            });
            return Ok(());
        }

        let mut stream = resp.bytes_stream();
        let mut buf = String::new();

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            buf.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(end) = frame_end(&buf) {
                let frame: String = buf.drain(..end).collect();
                // Drop the blank line that terminated it.
                while buf.starts_with('\r') || buf.starts_with('\n') {
                    buf.remove(0);
                }
                if let Some(event) = parse_frame(&frame) {
                    on_event(event);
                }
            }
        }

        // A trailing frame the server never closed with a blank line.
        if let Some(event) = parse_frame(&buf) {
            on_event(event);
        }

        Ok(())
    }
}

// ── Client ────────────────────────────────────────────────────────────────────

/// Top-level MisarReach client. Cheap to clone via the shared inner `Arc`.
pub struct MisarReachClient {
    pub leads: LeadsResource,
    pub deals: DealsResource,
    pub pipeline: PipelineResource,
    pub channels: ChannelsResource,
    pub autopilot: AutopilotResource,
    pub sales_agent: SalesAgentResource,
    pub campaigns: CampaignsResource,
    pub contacts: ContactsResource,
    pub conversations: ConversationsResource,
    pub workspaces: WorkspacesResource,
    pub settings: SettingsResource,
    pub plan: PlanResource,
    pub ads: AdsResource,
    pub campaign_templates: CampaignTemplatesResource,
    pub deliverability: DeliverabilityResource,
    pub notifications: NotificationsResource,
    pub webhooks: WebhooksResource,
}

impl MisarReachClient {
    /// Create a client with the default base URL (`https://api.misar.io/reach/api`).
    pub fn new(api_key: &str) -> Self {
        Self::build(api_key, DEFAULT_BASE_URL, DEFAULT_MAX_RETRIES)
    }

    /// Override the base URL (e.g. `https://api.misar.io/reach/api`).
    pub fn with_base_url(self, url: &str) -> Self {
        let inner = &self.leads.0;
        Self::build(&inner.api_key, url, inner.max_retries)
    }

    /// Override the maximum number of attempts per request.
    pub fn with_max_retries(self, n: u32) -> Self {
        let inner = &self.leads.0;
        Self::build(&inner.api_key, &inner.base_url.clone(), n)
    }

    fn build(api_key: &str, base_url: &str, max_retries: u32) -> Self {
        let inner = Arc::new(Inner::new(api_key, base_url, max_retries));
        Self {
            leads: LeadsResource(Arc::clone(&inner)),
            deals: DealsResource(Arc::clone(&inner)),
            pipeline: PipelineResource(Arc::clone(&inner)),
            channels: ChannelsResource(Arc::clone(&inner)),
            autopilot: AutopilotResource(Arc::clone(&inner)),
            sales_agent: SalesAgentResource(Arc::clone(&inner)),
            campaigns: CampaignsResource(Arc::clone(&inner)),
            contacts: ContactsResource(Arc::clone(&inner)),
            conversations: ConversationsResource(Arc::clone(&inner)),
            workspaces: WorkspacesResource(Arc::clone(&inner)),
            settings: SettingsResource(Arc::clone(&inner)),
            plan: PlanResource(Arc::clone(&inner)),
            ads: AdsResource(Arc::clone(&inner)),
            campaign_templates: CampaignTemplatesResource(Arc::clone(&inner)),
            deliverability: DeliverabilityResource(Arc::clone(&inner)),
            notifications: NotificationsResource(Arc::clone(&inner)),
            webhooks: WebhooksResource(Arc::clone(&inner)),
        }
    }
}

// ── Resource: Lead Finder ───────────────────────────────────────────────────────

/// Lead Finder — search/discover/enrich/verify/score leads, lists, saved
/// searches, scoring rules, recommendations, and the SSE job stream.
pub struct LeadsResource(Arc<Inner>);

impl LeadsResource {
    /// GET /lead-finder/account
    pub async fn account(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/account", Value::Null).await
    }

    /// GET /lead-finder/config
    pub async fn config(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/config", Value::Null).await
    }

    /// POST /lead-finder/search — start a lead search job.
    pub async fn search(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/search", Some(data)).await
    }

    /// POST /lead-finder/discover — discover leads from criteria.
    pub async fn discover(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/discover", Some(data)).await
    }

    /// POST /lead-finder/enrich
    pub async fn enrich(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/enrich", Some(data)).await
    }

    /// POST /lead-finder/verify
    pub async fn verify(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/verify", Some(data)).await
    }

    /// POST /lead-finder/score
    pub async fn score(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/score", Some(data)).await
    }

    /// GET /lead-finder/leads
    pub async fn leads(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/leads", params).await
    }

    /// GET /lead-finder/export
    pub async fn export(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/export", params).await
    }

    /// GET /lead-finder/recommendations
    pub async fn recommendations(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/recommendations", params).await
    }

    /// GET /lead-finder/search-history
    pub async fn search_history(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/search-history", params).await
    }

    /// POST /lead-finder/preview-message
    pub async fn preview_message(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/preview-message", Some(data)).await
    }

    /// POST /lead-finder/send-to-campaign
    pub async fn send_to_campaign(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/send-to-campaign", Some(data)).await
    }

    /// POST /lead-finder/add-to-segment
    pub async fn add_to_segment(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/add-to-segment", Some(data)).await
    }

    // ── companies ──
    /// GET /lead-finder/companies/{domain}
    pub async fn company(&self, domain: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/lead-finder/companies/{}", domain), Value::Null).await
    }

    /// GET /lead-finder/companies/{domain}/people
    pub async fn company_people(&self, domain: &str, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/lead-finder/companies/{}/people", domain), params).await
    }

    // ── jobs ──
    /// GET /lead-finder/jobs/{jobId}
    pub async fn job(&self, job_id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/lead-finder/jobs/{}", job_id), Value::Null).await
    }

    /// POST /lead-finder/jobs/{jobId}/feedback
    pub async fn job_feedback(&self, job_id: &str, data: Value) -> Result<Value, ReachError> {
        self.0
            .request(Method::POST, &format!("/lead-finder/jobs/{}/feedback", job_id), Some(data))
            .await
    }

    /// GET /lead-finder/jobs/{jobId}/stream — Server-Sent Events.
    ///
    /// `on_event` is invoked per frame with the server's event name attached:
    /// `progress`, `found`, `complete`, `error` or `timeout`. A job that has
    /// already finished is reported as a single `complete` (or `error`) frame,
    /// so the caller does not need to special-case it.
    ///
    /// ```no_run
    /// # async fn demo(reach: misarreach::MisarReachClient) -> Result<(), misarreach::ReachError> {
    /// reach.leads.stream("job_1", |ev| match ev.event.as_str() {
    ///     "progress" => println!("{}", ev.data),
    ///     "complete" => println!("done"),
    ///     _ => {}
    /// }).await
    /// # }
    /// ```
    pub async fn stream<F>(&self, job_id: &str, on_event: F) -> Result<(), ReachError>
    where
        F: FnMut(ReachSseEvent),
    {
        self.0.sse(&format!("/lead-finder/jobs/{}/stream", job_id), on_event).await
    }

    // ── lists ──
    /// GET /lead-finder/lists
    pub async fn lists(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/lists", Value::Null).await
    }

    /// POST /lead-finder/lists
    pub async fn create_list(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/lists", Some(data)).await
    }

    /// POST /lead-finder/lists/{listId}/sync
    pub async fn sync_list(&self, list_id: &str, data: Value) -> Result<Value, ReachError> {
        self.0
            .request(Method::POST, &format!("/lead-finder/lists/{}/sync", list_id), Some(data))
            .await
    }

    // ── saved searches ──
    /// GET /lead-finder/saved-searches
    pub async fn saved_searches(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/saved-searches", Value::Null).await
    }

    /// POST /lead-finder/saved-searches
    pub async fn create_saved_search(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/saved-searches", Some(data)).await
    }

    /// DELETE /lead-finder/saved-searches/{id}
    pub async fn delete_saved_search(&self, id: &str) -> Result<Value, ReachError> {
        self.0
            .request(Method::DELETE, &format!("/lead-finder/saved-searches/{}", id), None)
            .await
    }

    // ── scoring rules ──
    /// GET /lead-finder/scoring-rules
    pub async fn scoring_rules(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/lead-finder/scoring-rules", Value::Null).await
    }

    /// POST /lead-finder/scoring-rules
    pub async fn create_scoring_rule(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/lead-finder/scoring-rules", Some(data)).await
    }

    /// PATCH /lead-finder/scoring-rules/{id}
    pub async fn update_scoring_rule(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0
            .request(Method::PATCH, &format!("/lead-finder/scoring-rules/{}", id), Some(data))
            .await
    }

    /// DELETE /lead-finder/scoring-rules/{id}
    pub async fn delete_scoring_rule(&self, id: &str) -> Result<Value, ReachError> {
        self.0
            .request(Method::DELETE, &format!("/lead-finder/scoring-rules/{}", id), None)
            .await
    }
}

// ── Resource: Deals ─────────────────────────────────────────────────────────────

pub struct DealsResource(Arc<Inner>);

impl DealsResource {
    /// GET /deals
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/deals", params).await
    }

    /// POST /deals
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/deals", Some(data)).await
    }

    /// PATCH /deals/{id}
    pub async fn update(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, &format!("/deals/{}", id), Some(data)).await
    }

    /// DELETE /deals/{id}
    pub async fn delete(&self, id: &str) -> Result<Value, ReachError> {
        self.0.request(Method::DELETE, &format!("/deals/{}", id), None).await
    }

    /// GET /deals/{id}/activity
    pub async fn activity(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/deals/{}/activity", id), Value::Null).await
    }

    /// GET /deals/{id}/suggestions
    pub async fn suggestions(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/deals/{}/suggestions", id), Value::Null).await
    }

    /// POST /deals/bulk — one operation over many deals,
    /// `{"ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...}`. Tag writes
    /// are applied atomically server-side, so concurrent callers cannot lose a tag.
    pub async fn bulk(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/deals/bulk", Some(data)).await
    }
}

// ── Resource: Pipeline ──────────────────────────────────────────────────────────

pub struct PipelineResource(Arc<Inner>);

impl PipelineResource {
    /// GET /pipeline
    pub async fn get(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/pipeline", params).await
    }

    /// POST /pipeline
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/pipeline", Some(data)).await
    }
}

// ── Resource: Channels ──────────────────────────────────────────────────────────

/// Multi-channel outreach connections (SMS, WhatsApp, Telegram, Twitter,
/// Instagram, Facebook, Discord, web push) plus status and opt-in links.
pub struct ChannelsResource(Arc<Inner>);

impl ChannelsResource {
    /// GET /channels/status
    pub async fn status(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/channels/status", Value::Null).await
    }

    /// PATCH /channels/status
    pub async fn update_status(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, "/channels/status", Some(data)).await
    }

    /// GET /channels/opt-in-links
    pub async fn opt_in_links(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/channels/opt-in-links", params).await
    }

    /// POST /channels/sms/connect
    pub async fn connect_sms(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/sms/connect", Some(data)).await
    }

    /// POST /channels/whatsapp/connect
    pub async fn connect_whatsapp(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/whatsapp/connect", Some(data)).await
    }

    /// POST /channels/telegram/connect
    pub async fn connect_telegram(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/telegram/connect", Some(data)).await
    }

    /// POST /channels/twitter/connect
    pub async fn connect_twitter(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/twitter/connect", Some(data)).await
    }

    /// POST /channels/instagram/connect
    pub async fn connect_instagram(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/instagram/connect", Some(data)).await
    }

    /// POST /channels/facebook/connect
    pub async fn connect_facebook(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/facebook/connect", Some(data)).await
    }

    /// POST /channels/discord/connect
    pub async fn connect_discord(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/discord/connect", Some(data)).await
    }

    /// POST /channels/push/subscribe
    pub async fn subscribe_push(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/channels/push/subscribe", Some(data)).await
    }

    /// DELETE /channels/push/subscribe
    pub async fn unsubscribe_push(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::DELETE, "/channels/push/subscribe", Some(data)).await
    }
}

// ── Resource: Autopilot ─────────────────────────────────────────────────────────

pub struct AutopilotResource(Arc<Inner>);

impl AutopilotResource {
    /// POST /autopilot/start
    pub async fn start(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/autopilot/start", Some(data)).await
    }

    /// GET /autopilot/runs
    pub async fn runs(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/autopilot/runs", params).await
    }

    /// GET /autopilot/{id}
    pub async fn get(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/autopilot/{}", id), Value::Null).await
    }

    /// GET /autopilot/{id}/status
    pub async fn status(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/autopilot/{}/status", id), Value::Null).await
    }

    /// POST /autopilot/{id}/status — pause/resume/stop a run.
    pub async fn update_status(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, &format!("/autopilot/{}/status", id), Some(data)).await
    }
}

// ── Resource: Sales Agent ───────────────────────────────────────────────────────

pub struct SalesAgentResource(Arc<Inner>);

impl SalesAgentResource {
    /// GET /sales-agent/config
    pub async fn config(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/sales-agent/config", Value::Null).await
    }

    /// PATCH /sales-agent/config
    pub async fn update_config(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, "/sales-agent/config", Some(data)).await
    }

    /// GET /sales-agent/actions
    pub async fn actions(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/sales-agent/actions", params).await
    }

    /// GET /sales-agent/conversations
    pub async fn conversations(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/sales-agent/conversations", params).await
    }

    /// POST /sales-agent/process
    pub async fn process(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/sales-agent/process", Some(data)).await
    }
}

// ── Resource: Campaigns ─────────────────────────────────────────────────────────

pub struct CampaignsResource(Arc<Inner>);

impl CampaignsResource {
    /// GET /campaigns
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/campaigns", params).await
    }

    /// POST /campaigns
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/campaigns", Some(data)).await
    }

    /// GET /campaigns/{id}
    pub async fn get(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/campaigns/{}", id), Value::Null).await
    }

    /// PATCH /campaigns/{id}
    pub async fn update(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, &format!("/campaigns/{}", id), Some(data)).await
    }

    /// DELETE /campaigns/{id}
    pub async fn delete(&self, id: &str) -> Result<Value, ReachError> {
        self.0.request(Method::DELETE, &format!("/campaigns/{}", id), None).await
    }

    /// POST /campaigns/{id}/enqueue — flush queued sends.
    pub async fn enqueue(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, &format!("/campaigns/{}/enqueue", id), Some(data)).await
    }
}

// ── Resource: Contacts ──────────────────────────────────────────────────────────

pub struct ContactsResource(Arc<Inner>);

impl ContactsResource {
    /// GET /contacts
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/contacts", params).await
    }

    /// POST /contacts
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/contacts", Some(data)).await
    }

    /// GET /contacts/{id}
    pub async fn get(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/contacts/{}", id), Value::Null).await
    }

    /// PATCH /contacts/{id}
    pub async fn update(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, &format!("/contacts/{}", id), Some(data)).await
    }

    /// DELETE /contacts/{id}
    pub async fn delete(&self, id: &str) -> Result<Value, ReachError> {
        self.0.request(Method::DELETE, &format!("/contacts/{}", id), None).await
    }

    /// POST /contacts/bulk
    pub async fn bulk(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/contacts/bulk", Some(data)).await
    }

    /// POST /contacts/import
    pub async fn import_contacts(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/contacts/import", Some(data)).await
    }

    /// GET /contacts/segments
    pub async fn segments(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/contacts/segments", params).await
    }

    /// GET /contacts/stats
    pub async fn stats(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/contacts/stats", params).await
    }
}

// ── Resource: Conversations ─────────────────────────────────────────────────────

pub struct ConversationsResource(Arc<Inner>);

impl ConversationsResource {
    /// GET /conversations
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/conversations", params).await
    }

    /// GET /conversations/{email}
    pub async fn get(&self, email: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/conversations/{}", email), Value::Null).await
    }

    /// POST /conversations/{email}/reply
    pub async fn reply(&self, email: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, &format!("/conversations/{}/reply", email), Some(data)).await
    }
}

// ── Resource: Campaign templates ────────────────────────────────────────────────

/// Reusable campaign templates.
pub struct CampaignTemplatesResource(Arc<Inner>);

impl CampaignTemplatesResource {
    /// GET /campaign-templates
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/campaign-templates", params).await
    }

    /// POST /campaign-templates
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/campaign-templates", Some(data)).await
    }
}

// ── Resource: Deliverability ────────────────────────────────────────────────────

/// Sender health — bounce and complaint rates over a rolling window.
pub struct DeliverabilityResource(Arc<Inner>);

impl DeliverabilityResource {
    /// GET /deliverability
    ///
    /// `bounceRate` and `complaintRate` are null when there is not enough volume
    /// to judge — which is not the same as zero.
    pub async fn get(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/deliverability", params).await
    }
}

// ── Resource: Notifications ─────────────────────────────────────────────────────

/// In-app notifications.
pub struct NotificationsResource(Arc<Inner>);

impl NotificationsResource {
    /// GET /notifications
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/notifications", params).await
    }

    /// PATCH /notifications — pass `{"ids": [...]}` or `{"all": true}`.
    pub async fn mark_read(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PATCH, "/notifications", Some(data)).await
    }
}

// ── Resource: Webhooks ──────────────────────────────────────────────────────────

/// Outbound webhook endpoints.
pub struct WebhooksResource(Arc<Inner>);

impl WebhooksResource {
    /// GET /webhooks/endpoints
    pub async fn list(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/webhooks/endpoints", Value::Null).await
    }

    /// POST /webhooks/endpoints
    ///
    /// The response carries the signing secret exactly once — store it then; it
    /// is not retrievable afterwards.
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/webhooks/endpoints", Some(data)).await
    }
}

// ── Resource: Workspaces ────────────────────────────────────────────────────────

pub struct WorkspacesResource(Arc<Inner>);

impl WorkspacesResource {
    /// GET /workspaces
    pub async fn list(&self, params: Value) -> Result<Value, ReachError> {
        self.0.get_with_params("/workspaces", params).await
    }

    /// POST /workspaces
    pub async fn create(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/workspaces", Some(data)).await
    }

    /// GET /workspaces/{id}/members
    pub async fn members(&self, id: &str) -> Result<Value, ReachError> {
        self.0.get_with_params(&format!("/workspaces/{}/members", id), Value::Null).await
    }

    /// POST /workspaces/{id}/members
    pub async fn add_member(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, &format!("/workspaces/{}/members", id), Some(data)).await
    }

    /// DELETE /workspaces/{id}/members — member id supplied in the body.
    pub async fn remove_member(&self, id: &str, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::DELETE, &format!("/workspaces/{}/members", id), Some(data)).await
    }
}

// ── Resource: Settings ──────────────────────────────────────────────────────────

/// The subscription behind the API key.
///
/// Read this before an expensive run rather than discovering the ceiling through
/// [`ReachError::UpgradeRequired`] halfway through: a 402 says a call *was*
/// refused, whereas `usage` says what is left before anything is spent.
pub struct PlanResource(Arc<Inner>);

impl PlanResource {
    /// `GET /plan` — plan, caps, per-feature usage and the upgrade offer.
    ///
    /// A null limit means unlimited, and `remaining` is null with it rather than
    /// 0 — 0 would read as exhausted.
    pub async fn get(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/plan", Value::Null).await
    }
}

pub struct SettingsResource(Arc<Inner>);

impl SettingsResource {
    /// GET /settings/sender-address
    pub async fn get_sender_address(&self) -> Result<Value, ReachError> {
        self.0.get_with_params("/settings/sender-address", Value::Null).await
    }

    /// PUT /settings/sender-address
    pub async fn set_sender_address(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::PUT, "/settings/sender-address", Some(data)).await
    }
}

// ── Resource: Ads ───────────────────────────────────────────────────────────────

pub struct AdsResource(Arc<Inner>);

impl AdsResource {
    /// POST /ads/linkedin/company-audience
    pub async fn linkedin_company_audience(&self, data: Value) -> Result<Value, ReachError> {
        self.0.request(Method::POST, "/ads/linkedin/company-audience", Some(data)).await
    }
}

// ── Server-Sent Events ────────────────────────────────────────────────────────

/// One frame from the lead-finder progress stream.
///
/// MisarReach names its events, unlike the unnamed-frame dialect used
/// elsewhere, so [`event`](Self::event) is the field callers switch on.
#[derive(Debug, Clone, PartialEq)]
pub struct ReachSseEvent {
    /// The server's `event:` name — `progress`, `found`, `complete`, `error` or
    /// `timeout`. `message` when a frame carries no name, per the SSE default.
    pub event: String,
    /// Decoded payload, or a JSON string when the frame was not JSON.
    pub data: Value,
    /// The payload exactly as received.
    pub raw: String,
}

/// Offset of the blank line ending the first complete frame.
fn frame_end(buf: &str) -> Option<usize> {
    match (buf.find("\n\n"), buf.find("\r\n\r\n")) {
        (None, None) => None,
        (Some(lf), None) => Some(lf),
        (None, Some(crlf)) => Some(crlf),
        (Some(lf), Some(crlf)) => Some(lf.min(crlf)),
    }
}

/// Parses one frame, or `None` for a keepalive comment or a frame with no data.
fn parse_frame(frame: &str) -> Option<ReachSseEvent> {
    let mut event = String::new();
    let mut data_lines: Vec<&str> = Vec::new();

    for line in frame.split('\n') {
        let line = line.trim_end_matches('\r');
        if line.is_empty() || line.starts_with(':') {
            continue; // blank or keepalive comment
        }
        if let Some(rest) = line.strip_prefix("event:") {
            event = rest.trim().to_owned();
        } else if let Some(rest) = line.strip_prefix("data:") {
            // SSE strips exactly one space after the colon.
            data_lines.push(rest.strip_prefix(' ').unwrap_or(rest));
        }
    }

    if data_lines.is_empty() {
        return None;
    }

    let raw = data_lines.join("\n");
    let data = serde_json::from_str::<Value>(&raw)
        .unwrap_or_else(|_| Value::String(raw.clone()));

    Some(ReachSseEvent {
        event: if event.is_empty() { "message".to_owned() } else { event },
        data,
        raw,
    })
}
