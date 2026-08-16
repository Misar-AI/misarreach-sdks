// Package misarreach is the official Go SDK for the MisarReach Developer API —
// lead finder (23 sources), multi-channel outreach, deals/pipeline CRM,
// autopilot, and the AI sales agent.
//
// Auth uses a reach developer key (mrk_…), validated only against the
// reach-owned key table, so a key from any other Misar product is rejected.
package misarreach

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	defaultBaseURL    = "https://api.misar.io/reach/api"
	defaultMaxRetries = 3
	defaultTimeout    = 30 * time.Second
	retryBaseMS       = 200 * time.Millisecond
)

var retryable = map[int]bool{429: true, 500: true, 502: true, 503: true, 504: true}

// Response is the generic decoded JSON object returned by most endpoints.
// The reach contract intentionally leaves response bodies open, so callers
// read the fields they need.
type Response = map[string]interface{}

// ── Options ──────────────────────────────────────────────────────────────────────

type Option func(*Client)

// WithBaseURL overrides the default base URL (https://api.misar.io/reach/api).
func WithBaseURL(u string) Option {
	return func(c *Client) { c.baseURL = strings.TrimRight(u, "/") }
}

// WithMaxRetries sets the number of attempts for retryable (429/5xx) responses.
func WithMaxRetries(n int) Option { return func(c *Client) { c.maxRetries = n } }

// WithTimeout sets the per-request timeout on the default HTTP client.
func WithTimeout(d time.Duration) Option {
	return func(c *Client) { c.httpClient = &http.Client{Timeout: d} }
}

// WithHTTPClient supplies a custom *http.Client.
func WithHTTPClient(h *http.Client) Option { return func(c *Client) { c.httpClient = h } }

// ── Client ───────────────────────────────────────────────────────────────────────

type Client struct {
	apiKey     string
	baseURL    string
	maxRetries int
	httpClient *http.Client

	Leads         *LeadsResource
	Deals         *DealsResource
	Pipeline      *PipelineResource
	Channels      *ChannelsResource
	Autopilot     *AutopilotResource
	SalesAgent    *SalesAgentResource
	Campaigns     *CampaignsResource
	Contacts      *ContactsResource
	Conversations *ConversationsResource
	Settings      *SettingsResource
	Workspaces    *WorkspacesResource
	Ads           *AdsResource

	CampaignTemplates *CampaignTemplatesResource
	Deliverability    *DeliverabilityResource
	Notifications     *NotificationsResource
	Webhooks          *WebhooksResource
}

// New builds a client for the given reach developer key (mrk_…).
func New(apiKey string, opts ...Option) *Client {
	c := &Client{
		apiKey:     apiKey,
		baseURL:    defaultBaseURL,
		maxRetries: defaultMaxRetries,
		httpClient: &http.Client{Timeout: defaultTimeout},
	}
	for _, o := range opts {
		o(c)
	}
	c.Leads = &LeadsResource{c}
	c.Deals = &DealsResource{c}
	c.Pipeline = &PipelineResource{c}
	c.Channels = &ChannelsResource{c}
	c.Autopilot = &AutopilotResource{c}
	c.SalesAgent = &SalesAgentResource{c}
	c.Campaigns = &CampaignsResource{c}
	c.Contacts = &ContactsResource{c}
	c.Conversations = &ConversationsResource{c}
	c.Settings = &SettingsResource{c}
	c.Workspaces = &WorkspacesResource{c}
	c.Ads = &AdsResource{c}
	c.CampaignTemplates = &CampaignTemplatesResource{c}
	c.Deliverability = &DeliverabilityResource{c}
	c.Notifications = &NotificationsResource{c}
	c.Webhooks = &WebhooksResource{c}
	return c
}

// ── Core HTTP ─────────────────────────────────────────────────────────────────────

func (c *Client) do(ctx context.Context, method, path string, body interface{}) (Response, error) {
	fullURL := c.baseURL + path
	var lastErr error
	for attempt := 0; attempt < c.maxRetries; attempt++ {
		var bodyReader io.Reader
		if body != nil {
			b, err := json.Marshal(body)
			if err != nil {
				return nil, err
			}
			bodyReader = bytes.NewReader(b)
		}
		req, err := http.NewRequestWithContext(ctx, method, fullURL, bodyReader)
		if err != nil {
			return nil, err
		}
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			lastErr = &NetworkError{Message: err.Error(), Cause: err}
			if attempt < c.maxRetries-1 {
				time.Sleep(retryBaseMS * (1 << attempt))
				continue
			}
			return nil, lastErr
		}

		if retryable[resp.StatusCode] && attempt < c.maxRetries-1 {
			io.Copy(io.Discard, resp.Body) //nolint:errcheck
			resp.Body.Close()
			time.Sleep(retryBaseMS * (1 << attempt))
			continue
		}

		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return nil, parseError(resp.StatusCode, raw)
		}
		if resp.StatusCode == http.StatusNoContent || len(bytes.TrimSpace(raw)) == 0 {
			return nil, nil
		}
		var out Response
		if err := json.Unmarshal(raw, &out); err != nil {
			return nil, fmt.Errorf("misarreach: decode: %w", err)
		}
		return out, nil
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, &NetworkError{Message: "max retries exceeded"}
}

// parseError decodes the standard Error envelope into an *APIError.
func parseError(status int, raw []byte) error {
	var env struct {
		Error      json.RawMessage `json:"error"`
		Message    string          `json:"message"`
		Code       string          `json:"code"`
		RetryAfter int             `json:"retryAfter"`
	}
	_ = json.Unmarshal(raw, &env)
	msg := ""
	if len(env.Error) > 0 {
		var s string
		if json.Unmarshal(env.Error, &s) == nil {
			msg = s
		} else {
			msg = string(env.Error) // field-error object (e.g. zod flatten)
		}
	}
	if msg == "" {
		msg = env.Message
	}
	if msg == "" {
		msg = http.StatusText(status)
	}
	return &APIError{Status: status, Message: msg, Code: env.Code, RetryAfter: env.RetryAfter}
}

// ── Query helper ──────────────────────────────────────────────────────────────────

func query(p Params) string {
	if len(p) == 0 {
		return ""
	}
	q := url.Values{}
	for k, v := range p {
		if v != "" {
			q.Set(k, v)
		}
	}
	if s := q.Encode(); s != "" {
		return "?" + s
	}
	return ""
}

func esc(s string) string { return url.PathEscape(s) }
