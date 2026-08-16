use std::sync::{Arc, Mutex};

use misarreach::{MisarReachClient, ReachError};
use serde_json::json;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn make_client(server: &MockServer) -> MisarReachClient {
    MisarReachClient::new("mrk_test")
        .with_base_url(&server.uri())
        .with_max_retries(3)
}

#[tokio::test]
async fn leads_search_success() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/lead-finder/search"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "jobId": "job_123", "status": "queued" })),
        )
        .mount(&server)
        .await;

    let client = make_client(&server);
    let resp = client
        .leads
        .search(json!({ "query": "SaaS founders" }))
        .await
        .expect("leads.search failed");

    assert_eq!(resp["jobId"], "job_123");
    assert_eq!(resp["status"], "queued");
}

#[tokio::test]
async fn contacts_list_with_params() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/contacts"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "data": [{ "id": "c1", "email": "a@b.com" }],
            "pagination": { "total": 1 }
        })))
        .mount(&server)
        .await;

    let client = make_client(&server);
    let resp = client
        .contacts
        .list(json!({ "page": 1, "limit": 50 }))
        .await
        .expect("contacts.list failed");

    assert_eq!(resp["data"][0]["email"], "a@b.com");
}

#[tokio::test]
async fn channels_status() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/channels/status"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "sms": { "connected": true }, "telegram": { "connected": false }
        })))
        .mount(&server)
        .await;

    let client = make_client(&server);
    let resp = client.channels.status().await.expect("channels.status failed");
    assert_eq!(resp["sms"]["connected"], true);
}

#[tokio::test]
async fn error_envelope_401() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/lead-finder/search"))
        .respond_with(ResponseTemplate::new(401).set_body_json(json!({
            "error": { "code": "unauthorized", "message": "Invalid API key" }
        })))
        .mount(&server)
        .await;

    let client = make_client(&server);
    let err = client
        .leads
        .search(json!({ "query": "x" }))
        .await
        .expect_err("expected error");

    match err {
        ReachError::Api { status, message } => {
            assert_eq!(status, 401);
            assert_eq!(message, "Invalid API key");
        }
        other => panic!("expected Api error, got {:?}", other),
    }
}

#[tokio::test]
async fn retry_503_then_success() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/lead-finder/search"))
        .respond_with(ResponseTemplate::new(503))
        .up_to_n_times(2)
        .mount(&server)
        .await;

    Mock::given(method("POST"))
        .and(path("/lead-finder/search"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "jobId": "job_retry" })))
        .mount(&server)
        .await;

    let client = make_client(&server);
    let resp = client
        .leads
        .search(json!({ "query": "retry" }))
        .await
        .expect("leads.search failed after retry");

    assert_eq!(resp["jobId"], "job_retry");
}

#[tokio::test]
async fn lead_job_sse_stream() {
    let server = MockServer::start().await;

    let sse_body = "data: {\"status\":\"running\",\"progress\":10}\n\n\
data: {\"status\":\"running\",\"progress\":100}\n\n\
data: [DONE]\n\n";

    Mock::given(method("GET"))
        .and(path("/lead-finder/jobs/job_1/stream"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("content-type", "text/event-stream")
                .set_body_string(sse_body),
        )
        .mount(&server)
        .await;

    let client = make_client(&server);
    let events = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&events);

    client
        .leads
        .stream("job_1", move |ev| sink.lock().unwrap().push(ev))
        .await
        .expect("stream failed");

    let collected = events.lock().unwrap();
    assert_eq!(collected.len(), 2);
    assert_eq!(collected[0]["progress"], 10);
    assert_eq!(collected[1]["progress"], 100);
}
