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

    /// Open the SSE stream for a lead-finder job and invoke `on_event` for every
    /// `data:` frame carrying a JSON object. Returns when the stream closes or a
    /// `[DONE]` sentinel is received.
    async fn sse<F>(&self, path: &str, mut on_event: F) -> Result<(), ReachError>
    where
        F: FnMut(Value),
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
            return Err(ReachError::Api {
                status: status.as_u16(),
                message: Self::extract_message(&text),
            });
        }

        let mut stream = resp.bytes_stream();
        let mut buf = String::new();

        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            buf.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(pos) = buf.find('\n') {
                let line: String = buf.drain(..=pos).collect();
                let line = line.trim_end_matches(['\r', '\n']);
                if let Some(data) = line.strip_prefix("data:") {
                    let data = data.trim();
                    if data.is_empty() {
                        continue;
                    }
                    if data == "[DONE]" {
                        return Ok(());
                    }
                    if let Ok(v) = serde_json::from_str::<Value>(data) {
                        on_event(v);
                    }
                }
            }
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

    /// Override the base URL (e.g. `https://reach.misar.io/api`).
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
    /// `on_event` is invoked for every JSON `data:` frame until the stream
    /// closes or a `[DONE]` sentinel arrives.
    pub async fn stream<F>(&self, job_id: &str, on_event: F) -> Result<(), ReachError>
    where
        F: FnMut(Value),
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
