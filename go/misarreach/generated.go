package misarreach

// Generated from scripts/sdk-endpoint-spec.json.
//
// Only the operations the hand-written resources lack. Methods are matched by
// (resource, name) rather than by path, because that is what collides at
// compile time — an earlier pass matched on paths and produced redeclarations.

import (
	"context"
	"net/http"
	"net/url"
)

// Remove calls DELETE /campaigns/:id.
func (r *CampaignsResource) Remove(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/campaigns/"+url.PathEscape(id), nil)
}

// Remove calls DELETE /contacts/:id.
func (r *ContactsResource) Remove(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/contacts/"+url.PathEscape(id), nil)
}

// Remove calls DELETE /deals/:id.
func (r *DealsResource) Remove(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/deals/"+url.PathEscape(id), nil)
}

// LeadFinderResource groups the generated leadFinder operations.
type LeadFinderResource struct{ c *Client }

// Company calls GET /lead-finder/companies/:id.
func (r *LeadFinderResource) Company(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/companies/"+url.PathEscape(id), nil)
}

// CompanyPeople calls GET /lead-finder/companies/:id/people.
func (r *LeadFinderResource) CompanyPeople(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/companies/"+url.PathEscape(id)+"/people", nil)
}

// Job calls GET /lead-finder/jobs/:id.
func (r *LeadFinderResource) Job(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodGet, "/lead-finder/jobs/"+url.PathEscape(id), nil)
}

// JobFeedback calls POST /lead-finder/jobs/:id/feedback.
func (r *LeadFinderResource) JobFeedback(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/jobs/"+url.PathEscape(id)+"/feedback", body)
}

// SyncList calls POST /lead-finder/lists/:id/sync.
func (r *LeadFinderResource) SyncList(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/lead-finder/lists/"+url.PathEscape(id)+"/sync", body)
}

// RemoveSavedSearch calls DELETE /lead-finder/saved-searches/:id.
func (r *LeadFinderResource) RemoveSavedSearch(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/lead-finder/saved-searches/"+url.PathEscape(id), nil)
}

// UpdateScoringRule calls PATCH /lead-finder/scoring-rules/:id.
func (r *LeadFinderResource) UpdateScoringRule(ctx context.Context, id string, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPatch, "/lead-finder/scoring-rules/"+url.PathEscape(id), body)
}

// RemoveScoringRule calls DELETE /lead-finder/scoring-rules/:id.
func (r *LeadFinderResource) RemoveScoringRule(ctx context.Context, id string) (Response, error) {
	return r.c.do(ctx, http.MethodDelete, "/lead-finder/scoring-rules/"+url.PathEscape(id), nil)
}

// ConnectDiscord calls POST /channels/discord/connect.
func (r *ChannelsResource) ConnectDiscord(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/discord/connect", body)
}

// ConnectFacebook calls POST /channels/facebook/connect.
func (r *ChannelsResource) ConnectFacebook(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/facebook/connect", body)
}

// ConnectInstagram calls POST /channels/instagram/connect.
func (r *ChannelsResource) ConnectInstagram(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/instagram/connect", body)
}

// ConnectSms calls POST /channels/sms/connect.
func (r *ChannelsResource) ConnectSms(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/sms/connect", body)
}

// ConnectTelegram calls POST /channels/telegram/connect.
func (r *ChannelsResource) ConnectTelegram(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/telegram/connect", body)
}

// ConnectTwitter calls POST /channels/twitter/connect.
func (r *ChannelsResource) ConnectTwitter(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/twitter/connect", body)
}

// ConnectWhatsapp calls POST /channels/whatsapp/connect.
func (r *ChannelsResource) ConnectWhatsapp(ctx context.Context, body interface{}) (Response, error) {
	return r.c.do(ctx, http.MethodPost, "/channels/whatsapp/connect", body)
}
