package misarreach

import (
	"context"
	"fmt"
	"net/http"
)

// ── Lead Finder ───────────────────────────────────────────────────────────────────

type LeadsResource struct{ c *Client }

func (r *LeadsResource) Account(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/account", nil)
}
func (r *LeadsResource) Config(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/config", nil)
}
func (r *LeadsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/leads"+query(params), nil)
}
func (r *LeadsResource) Search(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/search", body)
}
func (r *LeadsResource) Discover(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/discover", body)
}
func (r *LeadsResource) Enrich(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/enrich", body)
}
func (r *LeadsResource) Verify(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/verify", body)
}
func (r *LeadsResource) Score(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/score", body)
}
func (r *LeadsResource) Export(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/export"+query(params), nil)
}
func (r *LeadsResource) GetJob(ctx context.Context, jobID string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/jobs/"+esc(jobID), nil)
}
func (r *LeadsResource) SubmitFeedback(ctx context.Context, jobID string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/jobs/"+esc(jobID)+"/feedback", body)
}

// StreamJob consumes the lead-finder job SSE stream. Range over
// stream.Events(); progress events carry {message, total_found}, followed by a
// terminal complete or error event. Always Close() the stream.
func (r *LeadsResource) StreamJob(ctx context.Context, jobID string) (*SSEStream, error) {
	return r.c.streamJob(ctx, "/lead-finder/jobs/"+esc(jobID)+"/stream")
}

func (r *LeadsResource) SearchHistory(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/search-history", nil)
}
func (r *LeadsResource) Recommendations(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/recommendations", nil)
}
func (r *LeadsResource) PreviewMessage(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/preview-message", body)
}
func (r *LeadsResource) SendToCampaign(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/send-to-campaign", body)
}
func (r *LeadsResource) AddToSegment(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/add-to-segment", body)
}
func (r *LeadsResource) Company(ctx context.Context, domain string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/companies/"+esc(domain), nil)
}
func (r *LeadsResource) CompanyPeople(ctx context.Context, domain string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/companies/"+esc(domain)+"/people", nil)
}

func (r *LeadsResource) Lists(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/lists", nil)
}
func (r *LeadsResource) CreateList(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/lists", body)
}
func (r *LeadsResource) SyncList(ctx context.Context, listID string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/lists/"+esc(listID)+"/sync", body)
}

func (r *LeadsResource) SavedSearches(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/saved-searches", nil)
}
func (r *LeadsResource) CreateSavedSearch(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/saved-searches", body)
}
func (r *LeadsResource) DeleteSavedSearch(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/lead-finder/saved-searches/"+esc(id), nil)
}

func (r *LeadsResource) ScoringRules(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/scoring-rules", nil)
}
func (r *LeadsResource) CreateScoringRule(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/scoring-rules", body)
}
func (r *LeadsResource) UpdateScoringRule(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/lead-finder/scoring-rules/"+esc(id), body)
}
func (r *LeadsResource) DeleteScoringRule(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/lead-finder/scoring-rules/"+esc(id), nil)
}

// ── Deals ─────────────────────────────────────────────────────────────────────────

type DealsResource struct{ c *Client }

func (r *DealsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/deals"+query(params), nil)
}
func (r *DealsResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/deals", body)
}
func (r *DealsResource) Update(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/deals/"+esc(id), body)
}
func (r *DealsResource) Delete(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/deals/"+esc(id), nil)
}
func (r *DealsResource) Activity(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/deals/"+esc(id)+"/activity", nil)
}
func (r *DealsResource) Suggestions(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/deals/"+esc(id)+"/suggestions", nil)
}

// Bulk applies one operation to many deals at once —
// {"ids": [...], "op": "tag"|"untag"|"stage"|"delete", ...}. Tag writes are
// applied atomically server-side, so concurrent callers cannot lose a tag.
func (r *DealsResource) Bulk(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/deals/bulk", body)
}

// ── Pipeline ──────────────────────────────────────────────────────────────────────

type PipelineResource struct{ c *Client }

func (r *PipelineResource) Get(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/pipeline", nil)
}

// Move moves a deal to a new pipeline stage (drag-and-drop equivalent).
func (r *PipelineResource) Move(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/pipeline", body)
}

// ── Channels ──────────────────────────────────────────────────────────────────────

var channelConnectors = map[string]bool{
	"whatsapp": true, "sms": true, "telegram": true, "twitter": true,
	"instagram": true, "facebook": true, "discord": true,
}

type ChannelsResource struct{ c *Client }

func (r *ChannelsResource) Status(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/channels/status", nil)
}
func (r *ChannelsResource) UpdateStatus(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/channels/status", body)
}
func (r *ChannelsResource) OptInLinks(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/channels/opt-in-links", nil)
}

// Connect connects one channel. channel must be one of whatsapp, sms, telegram,
// twitter, instagram, facebook, discord.
func (r *ChannelsResource) Connect(ctx context.Context, channel string, body interface{}) (Response, error) {
	if !channelConnectors[channel] {
		return nil, fmt.Errorf("misarreach: unknown channel %q", channel)
	}
	return r.c.do(ctx, http.MethodPost, "/channels/"+channel+"/connect", body)
}
func (r *ChannelsResource) PushSubscribe(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/push/subscribe", body)
}
func (r *ChannelsResource) PushUnsubscribe(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/channels/push/subscribe", nil)
}

// ── Autopilot ─────────────────────────────────────────────────────────────────────

type AutopilotResource struct{ c *Client }

func (r *AutopilotResource) Start(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/autopilot/start", body)
}
func (r *AutopilotResource) Runs(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/autopilot/runs"+query(params), nil)
}
func (r *AutopilotResource) Get(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/autopilot/"+esc(id), nil)
}
func (r *AutopilotResource) Status(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/autopilot/"+esc(id)+"/status", nil)
}
func (r *AutopilotResource) SetStatus(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/autopilot/"+esc(id)+"/status", body)
}

// ── Sales Agent ───────────────────────────────────────────────────────────────────

type SalesAgentResource struct{ c *Client }

func (r *SalesAgentResource) Config(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/sales-agent/config", nil)
}
func (r *SalesAgentResource) UpdateConfig(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/sales-agent/config", body)
}
func (r *SalesAgentResource) Actions(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/sales-agent/actions"+query(params), nil)
}
func (r *SalesAgentResource) Conversations(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/sales-agent/conversations"+query(params), nil)
}
func (r *SalesAgentResource) Process(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/sales-agent/process", body)
}

// ── Campaigns ─────────────────────────────────────────────────────────────────────

type CampaignsResource struct{ c *Client }

func (r *CampaignsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/campaigns"+query(params), nil)
}
func (r *CampaignsResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/campaigns", body)
}
func (r *CampaignsResource) Get(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/campaigns/"+esc(id), nil)
}
func (r *CampaignsResource) Update(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/campaigns/"+esc(id), body)
}
func (r *CampaignsResource) Delete(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/campaigns/"+esc(id), nil)
}
func (r *CampaignsResource) Enqueue(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/campaigns/"+esc(id)+"/enqueue", body)
}

// ── Contacts ──────────────────────────────────────────────────────────────────────

type ContactsResource struct{ c *Client }

func (r *ContactsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/contacts"+query(params), nil)
}
func (r *ContactsResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/contacts", body)
}
func (r *ContactsResource) Get(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/contacts/"+esc(id), nil)
}
func (r *ContactsResource) Update(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/contacts/"+esc(id), body)
}
func (r *ContactsResource) Delete(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/contacts/"+esc(id), nil)
}
func (r *ContactsResource) Bulk(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/contacts/bulk", body)
}
func (r *ContactsResource) Import(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/contacts/import", body)
}
func (r *ContactsResource) Segments(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/contacts/segments", nil)
}
func (r *ContactsResource) Stats(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/contacts/stats", nil)
}

// ── Conversations ─────────────────────────────────────────────────────────────────

type ConversationsResource struct{ c *Client }

func (r *ConversationsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/conversations"+query(params), nil)
}
func (r *ConversationsResource) Get(ctx context.Context, email string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/conversations/"+esc(email), nil)
}
func (r *ConversationsResource) Reply(ctx context.Context, email string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/conversations/"+esc(email)+"/reply", body)
}

// ── Campaign templates ────────────────────────────────────────────────────────────

type CampaignTemplatesResource struct{ c *Client }

func (r *CampaignTemplatesResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/campaign-templates"+query(params), nil)
}
func (r *CampaignTemplatesResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/campaign-templates", body)
}

// ── Deliverability ────────────────────────────────────────────────────────────────

type DeliverabilityResource struct{ c *Client }

// Get reports sender health. bounceRate and complaintRate are null when there is
// not enough volume to judge — which is not the same as zero.
func (r *DeliverabilityResource) Get(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/deliverability"+query(params), nil)
}

// ── Notifications ─────────────────────────────────────────────────────────────────

type NotificationsResource struct{ c *Client }

func (r *NotificationsResource) List(ctx context.Context, params Params) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/notifications"+query(params), nil)
}

// MarkRead marks notifications read. Pass {"ids": [...]} or {"all": true}.
func (r *NotificationsResource) MarkRead(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/notifications", body)
}

// ── Webhooks ──────────────────────────────────────────────────────────────────────

type WebhooksResource struct{ c *Client }

func (r *WebhooksResource) List(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/webhooks/endpoints", nil)
}

// Create registers an endpoint. The response carries the signing secret exactly
// once — store it then; it is not retrievable afterwards.
func (r *WebhooksResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/webhooks/endpoints", body)
}

// ── Settings ──────────────────────────────────────────────────────────────────────

type SettingsResource struct{ c *Client }

func (r *SettingsResource) SenderAddress(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/settings/sender-address", nil)
}
func (r *SettingsResource) SetSenderAddress(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPut, "/settings/sender-address", body)
}

// ── Workspaces ────────────────────────────────────────────────────────────────────

type WorkspacesResource struct{ c *Client }

func (r *WorkspacesResource) List(ctx context.Context) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/workspaces", nil)
}
func (r *WorkspacesResource) Create(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/workspaces", body)
}
func (r *WorkspacesResource) Members(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/workspaces/"+esc(id)+"/members", nil)
}
func (r *WorkspacesResource) AddMember(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/workspaces/"+esc(id)+"/members", body)
}
func (r *WorkspacesResource) RemoveMember(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/workspaces/"+esc(id)+"/members", body)
}

// ── Ads ───────────────────────────────────────────────────────────────────────────

type AdsResource struct{ c *Client }

func (r *AdsResource) LinkedInCompanyAudience(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/ads/linkedin/company-audience", body)
}
