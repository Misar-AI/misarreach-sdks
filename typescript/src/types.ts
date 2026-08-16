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

export interface JobStatusResponse {
  job: LeadSearchJob;
  results: Lead[];
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

export interface VerifyEmailsResponse {
  results: Array<{
    email: string;
    status: string;
    deliverable: boolean;
  }>;
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
