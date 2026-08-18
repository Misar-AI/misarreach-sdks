use thiserror::Error;

/// Errors returned by the MisarReach SDK.
///
/// The API always emits a standard error envelope:
/// `{ "error": { "code": "...", "message": "..." } }` (a bare `message`/`error`
/// string is also tolerated). [`ReachError::Api`] carries the HTTP status plus
/// the extracted message.
#[derive(Debug, Error)]
pub enum ReachError {
    #[error("API error {status}: {message}")]
    Api { status: u16, message: String },

    /// A counted plan cap was hit.
    ///
    /// MisarReach answers 402 with `upgrade: true` when a cap is reached —
    /// searches, results, autopilot runs, deals, seats, channels — and names
    /// the offending counter. Retrying cannot help until the cap resets or the
    /// plan changes.
    ///
    /// Distinct from the 503 `retry: true` the server sends when it could not
    /// *check* the quota: that one is retried, so "we do not know" is never
    /// mistaken for "you are over your limit".
    #[error("Upgrade required ({status}): {message}")]
    UpgradeRequired {
        status: u16,
        message: String,
        /// The counter that was exhausted, e.g. `lead_searches`.
        feature: Option<String>,
        /// The cap on the current plan.
        limit: Option<i64>,
        /// Usage against that cap when the call was refused.
        current: Option<i64>,
        /// Absolute URL to the billing page.
        upgrade_url: Option<String>,
    },

    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

impl ReachError {
    /// The billing URL to send the user to, when this is a plan refusal.
    pub fn upgrade_url(&self) -> Option<&str> {
        match self {
            ReachError::UpgradeRequired { upgrade_url, .. } => upgrade_url.as_deref(),
            _ => None,
        }
    }
}
