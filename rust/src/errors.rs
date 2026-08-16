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

    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}
