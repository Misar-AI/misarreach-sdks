package misarreach_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/Misar-AI/misarreach-sdks/go/misarreach"
)

func newTestClient(server *httptest.Server) *misarreach.Client {
	return misarreach.New("mrk_test",
		misarreach.WithBaseURL(server.URL),
		misarreach.WithMaxRetries(3),
		misarreach.WithHTTPClient(server.Client()),
	)
}

func TestLeadsSearch(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/lead-finder/search" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"jobId": "job_123", "status": "queued"})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	resp, err := c.Leads.Search(context.Background(), &misarreach.SearchLeadsRequest{Query: "SaaS founders", UseAI: true})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp["jobId"] != "job_123" {
		t.Errorf("expected jobId job_123, got %v", resp["jobId"])
	}
}

func TestLeadsListQuery(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("page") != "2" {
			t.Errorf("expected page=2, got %q", r.URL.Query().Get("page"))
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"leads": []any{}, "total": 0})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	_, err := c.Leads.List(context.Background(), misarreach.Params{"page": "2", "limit": "50"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDealsCreate(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/deals" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"id": "deal_1", "value": 5000})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	resp, err := c.Deals.Create(context.Background(), &misarreach.CreateDealRequest{LeadEmail: "a@b.com", Value: 5000})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp["id"] != "deal_1" {
		t.Errorf("expected deal_1, got %v", resp["id"])
	}
}

func TestChannelsConnectValidation(t *testing.T) {
	c := misarreach.New("mrk_test")
	_, err := c.Channels.Connect(context.Background(), "myspace", map[string]any{})
	if err == nil {
		t.Fatal("expected error for unknown channel")
	}
}

func TestAPIError401(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]any{"error": "invalid key"})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	_, err := c.Leads.List(context.Background(), nil)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	apiErr, ok := err.(*misarreach.APIError)
	if !ok {
		t.Fatalf("expected *APIError, got %T", err)
	}
	if apiErr.Status != 401 || !apiErr.IsAuth() {
		t.Errorf("expected 401 auth error, got %d", apiErr.Status)
	}
}

func TestRateLimitRetryAfter(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusTooManyRequests)
		json.NewEncoder(w).Encode(map[string]any{"error": "slow down", "success": false, "retryAfter": 5})
	}))
	defer srv.Close()

	c := misarreach.New("mrk_test", misarreach.WithBaseURL(srv.URL),
		misarreach.WithHTTPClient(srv.Client()), misarreach.WithMaxRetries(1))
	_, err := c.Leads.Search(context.Background(), map[string]any{"query": "x"})
	apiErr, ok := err.(*misarreach.APIError)
	if !ok {
		t.Fatalf("expected *APIError, got %T", err)
	}
	if apiErr.RetryAfter != 5 || !apiErr.IsRateLimit() {
		t.Errorf("expected retryAfter 5 rate-limit, got %+v", apiErr)
	}
}

func TestRetry503(t *testing.T) {
	var counter atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if counter.Add(1) < 3 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"ok": true})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	resp, err := c.Pipeline.Get(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp["ok"] != true {
		t.Errorf("expected ok true, got %v", resp["ok"])
	}
	if counter.Load() != 3 {
		t.Errorf("expected 3 attempts, got %d", counter.Load())
	}
}

func TestStreamJob(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/lead-finder/jobs/job_1/stream" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("event: progress\ndata: {\"total_found\": 1}\n\nevent: complete\ndata: {\"total_found\": 2}\n\n"))
	}))
	defer srv.Close()

	c := newTestClient(srv)
	stream, err := c.Leads.StreamJob(context.Background(), "job_1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	defer stream.Close()

	var events []string
	for e := range stream.Events() {
		events = append(events, e.Event)
	}
	if len(events) != 2 || events[0] != "progress" || events[1] != "complete" {
		t.Errorf("expected [progress complete], got %v", events)
	}
	if stream.Err() != nil {
		t.Errorf("unexpected stream error: %v", stream.Err())
	}
}

func TestStreamJobFinishedSnapshot(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"status": "completed", "total_found": 9})
	}))
	defer srv.Close()

	c := newTestClient(srv)
	stream, err := c.Leads.StreamJob(context.Background(), "job_2")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	defer stream.Close()

	var n int
	var last misarreach.SSEEvent
	for e := range stream.Events() {
		n++
		last = e
	}
	if n != 1 || last.Event != "complete" {
		t.Errorf("expected 1 complete event, got %d/%s", n, last.Event)
	}
}
