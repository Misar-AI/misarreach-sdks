/** A response whose exact shape is defined by the endpoint, not the SDK. */
export type JsonObject = Record<string, unknown>;

/** Cursor/offset paged envelope used by the list endpoints. */
export interface Paged<T> {
  items: T[];
  total?: number;
  next_cursor?: string | null;
}

// ── Leads ─────────────────────────────────────────────────────────────────────

export interface Lead {
  id: string;
  name: string | null;
  email: string;
  role: string | null;
  company: string | null;
  linkedin_url: string | null;
  location: string | null;
  source: string | null;
  enriched: boolean;
  created_at: string;
  score: number | null;
  score_reason: string | null;
  verify_status: string | null;
  ai_message: string | null;
}

export interface ListLeadsParams {
  page?: number;
  limit?: number;
  search?: string;
  job_id?: string;
}

export interface ListLeadsResponse {
  leads: Lead[];
  total: number;
  page: number;
  limit: number;
}

export interface LeadSearchFilters {
  location?: string;
  role?: string;
  industry?: string;
  companySize?: string;
}

export interface SearchLeadsParams {
  query: string;
  useAI?: boolean;
  filters?: LeadSearchFilters;
}

export interface SearchLeadsResponse {
  jobId: string;
}

export interface LeadSearchJob {
  id: string;
  status: "pending" | "running" | "done" | "failed";
  total_found: number | null;
  error: string | null;
  progress: number | null;
  created_at: string;
  completed_at: string | null;
  query: string;
  filters: LeadSearchFilters | null;
}

/**
 * A business the search FOUND and did NOT qualify.
 *
 * NOT a `Lead`, and deliberately not shaped like one: no email, no id, no score.
 * It is stored on the job (not in the leads table), it is never returned in
 * `results`, and it must never be exported, added to a segment or mailed. It
 * exists so a search that qualifies nothing can show what it looked at and why
 * none of it counted, instead of an empty array.
 */
export interface NonQualifyingCandidate {
  business: string;
  location: string | null;
  phone: string | null;
  website: string | null;
  source: string;
  /** Plain-language reason this record did not qualify. */
  reason: string;
  reasons: string[];
}

export interface JobStatusResponse {
  job: LeadSearchJob;
  results: Lead[];
  /** Near-misses, separate from `results`. See {@link NonQualifyingCandidate}. */
  candidates: NonQualifyingCandidate[];
}

export interface JobFeedbackParams {
  jobId: string;
  leadEmail: string;
  feedback: "positive" | "negative";
}

export interface EnrichLeadParams {
  leadId: string;
}

export interface EnrichedPerson {
  name: string | null;
  position: string | null;
  seniority: string | null;
  department: string | null;
  linkedin_url: string | null;
  phone: string | null;
}

export interface EnrichedCompany {
  name: string | null;
  domain: string | null;
  industry: string | null;
  size: string | null;
  description: string | null;
  technologies: string[] | null;
}

export interface EnrichLeadResponse {
  enriched: boolean;
  person: EnrichedPerson;
  company: EnrichedCompany;
}

export interface VerifyEmailsParams {
  email?: string;
  emails?: string[];
}

/**
 * `valid`, `invalid`, `accept_all` (a catch-all domain: every address is
 * accepted, so this one cannot be confirmed — never treat it as valid),
 * `webmail`, `disposable` or `unknown`.
 */
export type EmailVerifyStatus = "valid" | "invalid" | "accept_all" | "webmail" | "disposable" | "unknown";

export interface VerifyEmailsResponse {
  results: Array<{
    email: string;
    /** `null` while the check is still pending. */
    status: EmailVerifyStatus | null;
    score: number | null;
    /** `true` on a catch-all domain (status is then `accept_all`); `null` when it could not be tested. */
    catch_all: boolean | null;
    /** `true` when the check could not finish yet — call again later. */
    pending: boolean;
    /** @deprecated Never returned by the API; read `status` instead. */
    deliverable?: boolean;
  }>;
  /** Addresses that got a verdict. */
  verified: number;
}

/** GET /lead-finder/companies/:domain/site — what a company's own website publishes. */
export interface CompanySiteReveal {
  domain: string;
  /** Pages actually read (0 = the site could not be read). */
  pages_checked: number;
  emails: string[];
  phone: { published: string; e164: string | null } | null;
  published_name: string | null;
  profiles: {
    linkedin: string | null;
    x: { url: string; handle: string | null } | null;
    instagram: string | null;
    facebook: string | null;
    github: string | null;
    youtube: string | null;
    telegram: string | null;
    whatsapp: string | null;
  };
  technologies: string[];
  technology_categories: Record<string, string[]>;
  /** Whether anything usable to reach the company was found. */
  has_contact: boolean;
  /** Whether this call consumed an enrichment credit. */
  charged: boolean;
}

/** The person a brief's outreach message is written to. All optional. */
export interface CompanyBriefParams {
  name?: string;
  role?: string;
  company?: string;
}

export interface CompanyBrief {
  core_offer: string;
  target_audience: string | null;
  /** A likely priority — an inference, labelled as one. */
  growth_bottleneck: string | null;
  email_opening_hook: string | null;
}

/** GET /lead-finder/suggest */
export interface SearchSuggestions {
  ok: true;
  /** At most six completions of what was typed; `[]` when there are none. */
  suggestions: string[];
}

/** A recent public fact about the company, with the pages it was read from. */
export interface CompanyRecentFact {
  fact: string;
  sources: string[];
}

/** POST /lead-finder/companies/:domain/brief */
export interface CompanyBriefResponse {
  domain: string;
  /** `null` when no brief could be written; `reason` and `note` then say why. */
  brief: CompanyBrief | null;
  /**
   * Up to five recent public facts (funding, launches, news, hiring), each with
   * its sources; `[]` when none are available. Absent from servers before 2026-10.
   */
  recent?: CompanyRecentFact[];
  reason?: "site_unreadable" | "not_enough_text" | "ai_unavailable" | "no_usable_answer";
  note?: string;
  /** The message for the named person, or `null` when no name was given. */
  message: string | null;
}

export interface EmailPatternShare {
  pattern: string;
  /** "{first}.{last}@acme.com", or null for the "other" bucket. */
  template: string | null;
  /** The pattern applied to the placeholder name Jane Doe. */
  example: string | null;
  count: number;
  /** 0..1 */
  share: number;
}

/** GET /public/email-formats/:domain — learned only from verified-deliverable addresses. */
export interface EmailFormatSummary {
  domain: string;
  verifiedAddresses: number;
  top: EmailPatternShare;
  patterns: EmailPatternShare[];
  confidence: "high" | "medium" | "low";
  computedAt: string;
}

export interface DiscoverCompaniesParams {
  query?: string;
  industry?: string[];
  location?: string[];
  headcount_min?: number;
  headcount_max?: number;
  technology?: string[];
  fetch_emails?: boolean;
  limit?: number;
}

export interface DiscoverCompaniesResponse {
  companies: Array<{
    name: string;
    domain: string;
    industry: string | null;
    headcount: number | null;
    emails?: string[];
  }>;
}

export interface ScoreLeadsParams {
  jobId?: string;
  leadIds?: string[];
}

export interface ScoreLeadsResponse {
  scored: number;
  status: string;
}

export interface LeadList {
  id: number;
  name: string;
  leads_count: number;
}

export interface LeadListsResponse {
  lists: LeadList[];
}

export interface SyncLeadListResponse {
  synced: number;
  listId: number;
}

export interface PreviewMessageParams {
  name: string;
  role?: string;
  company?: string;
}

export interface PreviewMessageResponse {
  message: string;
}

export interface SendToCampaignParams {
  leadIds: string[];
  campaignId: string;
  listId?: string;
}

export interface SendToCampaignResponse {
  imported: number;
  campaignId: string;
  listId: string;
}

// ── Deals ─────────────────────────────────────────────────────────────────────

export type DealStage =
  | "new"
  | "contacted"
  | "interested"
  | "meeting"
  | "proposal"
  | "closed"
  | "lost";

export type DealStatus = "interested" | "meeting" | "proposal" | "closed" | "lost";

export interface Deal {
  id: string;
  lead_email: string;
  lead_name: string | null;
  value: number;
  currency: string;
  status: string;
  stage?: DealStage;
  notes: string | null;
  conversation_id: string | null;
  campaign_id: string | null;
  created_at: string;
  closed_at: string | null;
}

export interface ListDealsParams {
  status?: string;
  limit?: number;
  offset?: number;
}

export interface RevenueSummary {
  total: number;
  closed: number;
  pipeline: number;
}

export interface ListDealsResponse {
  deals: Deal[];
  total: number;
  revenue: RevenueSummary;
}

export interface CreateDealParams {
  leadEmail: string;
  leadName?: string;
  conversationId?: string;
  campaignId?: string;
  contactId?: string;
  value?: number;
  currency?: string;
  notes?: string;
}

export interface CreateDealResponse {
  ok: boolean;
  deal: Pick<Deal, "id" | "status" | "lead_email" | "value">;
}

export interface UpdateDealParams {
  status?: DealStatus;
  value?: number;
  notes?: string;
}

export interface UpdateDealResponse {
  ok: boolean;
  deal: Pick<Deal, "id" | "status" | "value" | "lead_email">;
}

// ── Pipeline ──────────────────────────────────────────────────────────────────

export type PipelineBoard = Record<DealStage, Deal[]>;

export interface PipelineResponse {
  board: PipelineBoard;
  revenue: { pipeline: number; closed: number };
  stages: DealStage[];
}

export interface MoveDealParams {
  dealId: string;
  newStage: DealStage;
}

export interface MoveDealResponse {
  ok: boolean;
  deal: { id: string; stage: DealStage; lead_email: string };
}

// ── Channels ──────────────────────────────────────────────────────────────────

export interface ChannelStats {
  sent: number;
  delivered: number;
  failed: number;
  delivery_rate: number;
}

export interface WhatsAppChannelStatus {
  enabled: boolean;
  verified: boolean;
  phone_number_id: string | null;
  display_name: string | null;
  stats: ChannelStats;
}

export interface SmsChannelStatus {
  enabled: boolean;
  verified: boolean;
  number: string | null;
  provider: string;
  stats: ChannelStats;
}

export interface PushChannelStatus {
  enabled: boolean;
  vapid_configured: boolean;
  subscribers: number;
  stats: ChannelStats;
}

export interface ChannelsStatusResponse {
  success: boolean;
  data: {
    whatsapp: WhatsAppChannelStatus;
    sms: SmsChannelStatus;
    push: PushChannelStatus;
  };
}

export interface UpdateChannelParams {
  channel: "whatsapp" | "sms" | "push";
  enabled: boolean;
}

export interface UpdateChannelResponse {
  success: boolean;
  channel: string;
  enabled: boolean;
}

// ── Sales Agent ───────────────────────────────────────────────────────────────

export interface SalesAgentConfig {
  user_id: string;
  enabled: boolean;
  cal_link: string | null;
  offer_price: number;
  offer_description: string | null;
  max_replies_per_day: number;
  confidence_threshold: number;
}

export interface UpdateSalesAgentConfigParams {
  enabled?: boolean;
  cal_link?: string | null;
  offer_price?: number;
  offer_description?: string | null;
  max_replies_per_day?: number;
  confidence_threshold?: number;
}

export interface AgentAction {
  id: string;
  action: string;
  reason: string | null;
  confidence: number;
  flagged_human: boolean;
  auto_sent: boolean;
  created_at: string;
  conversation_id: string;
}

export interface SalesAgentActionsResponse {
  ok: boolean;
  actions: AgentAction[];
  stats: {
    total: number;
    deals: number;
    flagged: number;
  };
}

export interface AgentDecision {
  action: string;
  reason: string;
  confidence: number;
}

export interface ProcessSalesAgentResponse {
  ok: boolean;
  decision: AgentDecision;
  reply: string | null;
  flaggedHuman: boolean;
  todayCount: number;
  dailyLimit: number;
}

// ── Autopilot ─────────────────────────────────────────────────────────────────

export interface StartAutopilotParams {
  goal: string;
  workspace_id?: string | null;
}

export interface StartAutopilotResponse {
  ok: boolean;
  runId: string;
}

export interface AutopilotRun {
  id: string;
  status: "pending" | "running" | "done" | "failed" | "stopped";
  goal: string;
  created_at: string;
  completed_at: string | null;
  error: string | null;
}

export interface AutopilotRunsResponse {
  runs: AutopilotRun[];
  total: number;
}

export interface AutopilotStatusResponse {
  ok: boolean;
  run: AutopilotRun;
}
