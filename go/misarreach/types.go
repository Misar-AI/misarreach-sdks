package misarreach

import "fmt"

// Params is a generic query-string bag for list/GET endpoints.
// Nil or empty values are skipped when encoding.
type Params map[string]string

// ── Errors ──────────────────────────────────────────────────────────────────────

// APIError is returned for any non-2xx response carrying the standard Error
// envelope: { error, success?, message?, code?, retryAfter? }.
type APIError struct {
	Status     int    `json:"status"`
	Message    string `json:"message"`
	Code       string `json:"code,omitempty"`
	RetryAfter int    `json:"retryAfter,omitempty"`
}

func (e *APIError) Error() string {
	return fmt.Sprintf("misarreach: API error %d: %s", e.Status, e.Message)
}

// IsAuth reports a 401/403 (missing, invalid, or out-of-scope mrk_ key).
func (e *APIError) IsAuth() bool { return e.Status == 401 || e.Status == 403 }

// IsNotFound reports a 404.
func (e *APIError) IsNotFound() bool { return e.Status == 404 }

// IsRateLimit reports a 429.
func (e *APIError) IsRateLimit() bool { return e.Status == 429 }

// NetworkError is a transport-level failure (connection reset, timeout, DNS, …).
type NetworkError struct {
	Message string `json:"message"`
	Cause   error  `json:"-"`
}

func (e *NetworkError) Error() string {
	return fmt.Sprintf("misarreach: network error: %s", e.Message)
}
func (e *NetworkError) Unwrap() error { return e.Cause }

// ── Typed request bodies (optional; any JSON-serialisable value is accepted) ─────

// SearchLeadsRequest — POST /lead-finder/search.
type SearchLeadsRequest struct {
	Query              string                 `json:"query"`
	UseAI              bool                   `json:"useAI,omitempty"`
	Filters            map[string]interface{} `json:"filters,omitempty"`
	DisablePaidSources bool                   `json:"disablePaidSources,omitempty"`
}

// DiscoverCompaniesRequest — POST /lead-finder/discover.
type DiscoverCompaniesRequest struct {
	Query          string   `json:"query,omitempty"`
	Industry       []string `json:"industry,omitempty"`
	Location       []string `json:"location,omitempty"`
	HeadcountMin   int      `json:"headcount_min,omitempty"`
	HeadcountMax   int      `json:"headcount_max,omitempty"`
	Technology     []string `json:"technology,omitempty"`
	YearFoundedMin int      `json:"year_founded_min,omitempty"`
	YearFoundedMax int      `json:"year_founded_max,omitempty"`
	FetchEmails    bool     `json:"fetch_emails,omitempty"`
	Limit          int      `json:"limit,omitempty"`
	Offset         int      `json:"offset,omitempty"`
}

// EnrichLeadRequest — POST /lead-finder/enrich.
type EnrichLeadRequest struct {
	LeadID string `json:"leadId"`
}

// CreateDealRequest — POST /deals.
type CreateDealRequest struct {
	ConversationID string `json:"conversationId,omitempty"`
	CampaignID     string `json:"campaignId,omitempty"`
	ContactID      string `json:"contactId,omitempty"`
	LeadEmail      string `json:"leadEmail,omitempty"`
	LeadName       string `json:"leadName,omitempty"`
	Value          int    `json:"value,omitempty"`
	Currency       string `json:"currency,omitempty"`
	Notes          string `json:"notes,omitempty"`
}

// CreateCampaignRequest — POST /campaigns.
type CreateCampaignRequest struct {
	Name                string                   `json:"name"`
	Description         string                   `json:"description,omitempty"`
	AudienceFilter      map[string]interface{}   `json:"audience_filter,omitempty"`
	Steps               []map[string]interface{} `json:"steps,omitempty"`
	ScheduledAt         string                   `json:"scheduled_at,omitempty"`
	SendIntervalSeconds int                      `json:"send_interval_seconds,omitempty"`
}

// ContactsBulkRequest — POST /contacts/bulk.
type ContactsBulkRequest struct {
	Action string   `json:"action"`
	IDs    []string `json:"ids"`
}

// ContactsImportRequest — POST /contacts/import.
type ContactsImportRequest struct {
	Contacts       []map[string]interface{} `json:"contacts"`
	DefaultConsent map[string]interface{}   `json:"defaultConsent,omitempty"`
}
