export { MisarReachClient } from "./client.js";
export type { MisarReachClientOptions } from "./client.js";

// Resource classes are exported so callers can name them in their own types —
// e.g. accepting a `DealsResource` in a helper rather than the whole client.
export { AdsResource } from "./resources/ads.js";
export { AutopilotResource } from "./resources/autopilot.js";
export { CampaignTemplatesResource } from "./resources/campaignTemplates.js";
export { CampaignsResource } from "./resources/campaigns.js";
export { ChannelsResource } from "./resources/channels.js";
export { ContactsResource } from "./resources/contacts.js";
export { ConversationsResource } from "./resources/conversations.js";
export { DealsResource } from "./resources/deals.js";
export { DeliverabilityResource } from "./resources/deliverability.js";
export { LeadFinderResource } from "./resources/leadFinder.js";
export { LeadsResource } from "./resources/leads.js";
export { NotificationsResource } from "./resources/notifications.js";
export { SalesAgentResource } from "./resources/salesAgent.js";
export { SettingsResource } from "./resources/settings.js";
export { WebhooksResource } from "./resources/webhooks.js";
export { WorkspacesResource } from "./resources/workspaces.js";
export {
  MisarReachError,
  RateLimitError,
  AuthError,
  NotFoundError,
  UpgradeRequiredError,
} from "./errors.js";
export type {
  JsonObject,
  Paged,
  Lead,
  ListLeadsParams,
  ListLeadsResponse,
  LeadSearchFilters,
  SearchLeadsParams,
  SearchLeadsResponse,
  LeadSearchJob,
  JobStatusResponse,
  JobFeedbackParams,
  EnrichLeadParams,
  EnrichedPerson,
  EnrichedCompany,
  EnrichLeadResponse,
  VerifyEmailsParams,
  VerifyEmailsResponse,
  DiscoverCompaniesParams,
  DiscoverCompaniesResponse,
  ScoreLeadsParams,
  ScoreLeadsResponse,
  LeadList,
  LeadListsResponse,
  SyncLeadListResponse,
  PreviewMessageParams,
  PreviewMessageResponse,
  SendToCampaignParams,
  SendToCampaignResponse,
  DealStage,
  DealStatus,
  Deal,
  ListDealsParams,
  RevenueSummary,
  ListDealsResponse,
  CreateDealParams,
  CreateDealResponse,
  UpdateDealParams,
  UpdateDealResponse,
  PipelineBoard,
  PipelineResponse,
  MoveDealParams,
  MoveDealResponse,
  ChannelStats,
  WhatsAppChannelStatus,
  SmsChannelStatus,
  PushChannelStatus,
  ChannelsStatusResponse,
  UpdateChannelParams,
  UpdateChannelResponse,
  SalesAgentConfig,
  UpdateSalesAgentConfigParams,
  AgentAction,
  SalesAgentActionsResponse,
  AgentDecision,
  ProcessSalesAgentResponse,
  StartAutopilotParams,
  StartAutopilotResponse,
  AutopilotRun,
  AutopilotRunsResponse,
  AutopilotStatusResponse,
} from "./types.js";
export * from "./resources/plan.js";
