//! Optional strongly-typed request/response models.
//!
//! Every resource method accepts and returns [`serde_json::Value`] for maximum
//! flexibility; these structs are provided for callers who prefer typed
//! (de)serialization of common shapes. They mirror the MisarReach OpenAPI
//! schemas but are intentionally lenient (`#[serde(default)]`).

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── Error envelope ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorEnvelope {
    pub error: ErrorBody,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorBody {
    pub code: String,
    pub message: String,
    #[serde(default)]
    pub details: Option<serde_json::Value>,
}

// ── Lead Finder ─────────────────────────────────────────────────────────────────

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct LeadSearchRequest {
    pub query: String,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub sources: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "HashMap::is_empty", default)]
    pub filters: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LeadJob {
    pub id: String,
    pub status: String,
    #[serde(default)]
    pub progress: i64,
    #[serde(default)]
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Lead {
    pub id: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub first_name: Option<String>,
    #[serde(default)]
    pub last_name: Option<String>,
    #[serde(default)]
    pub company: Option<String>,
    #[serde(default)]
    pub job_title: Option<String>,
    #[serde(default)]
    pub lead_score: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LeadsListResponse {
    #[serde(default)]
    pub data: Vec<Lead>,
    #[serde(default)]
    pub total: i64,
}

/// A single Server-Sent Event frame from the lead-job stream.
#[derive(Debug, Serialize, Deserialize)]
pub struct LeadStreamEvent {
    #[serde(default)]
    pub job_id: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub progress: Option<i64>,
    #[serde(default)]
    pub lead: Option<Lead>,
}

// ── Deals / Pipeline ────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct Deal {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub stage: Option<String>,
    #[serde(default)]
    pub value: Option<f64>,
    #[serde(default)]
    pub currency: Option<String>,
    #[serde(default)]
    pub created_at: String,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct CreateDealRequest {
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contact_email: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PipelineStage {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub order: i64,
}

// ── Contacts ────────────────────────────────────────────────────────────────────

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ContactInput {
    pub email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub company: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub job_title: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Contact {
    pub id: String,
    pub email: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ContactsStats {
    #[serde(default)]
    pub total: i64,
    #[serde(default)]
    pub subscribed: i64,
}

// ── Channels ────────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct ChannelStatus {
    pub channel: String,
    pub connected: bool,
    #[serde(default)]
    pub enabled: bool,
}

// ── Autopilot ───────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct AutopilotRun {
    pub id: String,
    pub status: String,
    #[serde(default)]
    pub created_at: String,
}

// ── Campaigns ───────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct Campaign {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub channel: Option<String>,
}
