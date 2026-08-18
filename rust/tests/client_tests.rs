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

    // MisarReach names its events and sends `: keepalive` every 20s. It does
    // not send a [DONE] sentinel — the stream ends when the server closes it.
    let sse_body = "event: progress\ndata: {\"message\":\"searching\"}\n\n\
: keepalive\n\n\
event: found\ndata: {\"total\":12}\n\n\
event: complete\ndata: {\"total_found\":12}\n\n";

    Mock::given(method("GET"))
        .and(path("/lead-finder/jobs/job_1/stream"))
        .respond_with(
            ResponseTemplate::new(200).set_body_raw(sse_body, "text/event-stream"),
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
    let names: Vec<&str> = collected.iter().map(|e| e.event.as_str()).collect();

    // The keepalive comment must not surface as an event.
    assert_eq!(names, vec!["progress", "found", "complete"]);
    assert_eq!(collected[1].data["total"], 12);
}

#[tokio::test]
async fn lead_job_stream_reports_an_already_finished_job() {
    let server = MockServer::start().await;

    // A finished job is answered with a JSON snapshot rather than a stream.
    // Parsed as SSE this yields nothing, so the caller could not tell a
    // finished job from a silent one.
    Mock::given(method("GET"))
        .and(path("/lead-finder/jobs/job_done/stream"))
        .respond_with(
            ResponseTemplate::new(200).set_body_raw(r#"{"status":"done","total_found":42,"error":null}"#, "application/json"),
        )
        .mount(&server)
        .await;

    let client = make_client(&server);
    let events = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&events);

    client
        .leads
        .stream("job_done", move |ev| sink.lock().unwrap().push(ev))
        .await
        .expect("stream failed");

    let collected = events.lock().unwrap();
    assert_eq!(collected.len(), 1);
    assert_eq!(collected[0].event, "complete");
    assert_eq!(collected[0].data["total_found"], 42);
}

#[tokio::test]
async fn lead_job_stream_reports_a_failed_job_as_error() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/lead-finder/jobs/job_bad/stream"))
        .respond_with(
            ResponseTemplate::new(200).set_body_raw(r#"{"status":"failed","error":"no sources reachable"}"#, "application/json"),
        )
        .mount(&server)
        .await;

    let client = make_client(&server);
    let events = Arc::new(Mutex::new(Vec::new()));
    let sink = Arc::clone(&events);

    client
        .leads
        .stream("job_bad", move |ev| sink.lock().unwrap().push(ev))
        .await
        .expect("stream failed");

    let collected = events.lock().unwrap();
    assert_eq!(collected[0].event, "error");
}

#[tokio::test]
async fn lead_job_stream_refusal_is_typed() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/lead-finder/jobs/job_1/stream"))
        .respond_with(ResponseTemplate::new(402).set_body_string(
            r#"{"error":"monthly lead searches used up","upgrade":true,
                "feature":"lead_searches","limit":50,"current":50,
                "upgrade_url":"/settings?tab=billing"}"#,
        ))
        .mount(&server)
        .await;

    let client = make_client(&server);
    let err = client
        .leads
        .stream("job_1", |_| {})
        .await
        .expect_err("expected a refusal");

    // A plan refusal on the stream must be the same typed error the JSON
    // helper raises, not a generic Api error.
    match err {
        misarreach::ReachError::UpgradeRequired {
            status,
            ref feature,
            limit,
            current,
            ref upgrade_url,
            ..
        } => {
            assert_eq!(status, 402);
            assert_eq!(feature.as_deref(), Some("lead_searches"));
            assert_eq!(limit, Some(50));
            assert_eq!(current, Some(50));
            // The server sends it app-relative; the SDK resolves it.
            assert_eq!(
                upgrade_url.as_deref(),
                Some("https://misarreach.com/settings?tab=billing")
            );
        }
        other => panic!("expected UpgradeRequired, got {other:?}"),
    }
}
