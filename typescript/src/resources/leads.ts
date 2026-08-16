import type {
  ListLeadsParams,
  ListLeadsResponse,
  SearchLeadsParams,
  SearchLeadsResponse,
  JobStatusResponse,
  JobFeedbackParams,
  EnrichLeadParams,
  EnrichLeadResponse,
  VerifyEmailsParams,
  VerifyEmailsResponse,
  DiscoverCompaniesParams,
  DiscoverCompaniesResponse,
  ScoreLeadsParams,
  ScoreLeadsResponse,
  LeadListsResponse,
  LeadList,
  SyncLeadListResponse,
  PreviewMessageParams,
  PreviewMessageResponse,
  SendToCampaignParams,
  SendToCampaignResponse,
} from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class LeadsResource {
  constructor(private readonly request: Requester) {}

  /** List all saved leads for the authenticated user (paginated). */
  list(params?: ListLeadsParams): Promise<ListLeadsResponse> {
    const qs = new URLSearchParams();
    if (params?.page != null)  qs.set("page", String(params.page));
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.search)        qs.set("search", params.search);
    if (params?.job_id)        qs.set("job_id", params.job_id);
    const query = qs.toString();
    return this.request("GET", `/lead-finder/leads${query ? `?${query}` : ""}`);
  }

  /** Start an async lead search. Returns a jobId; poll jobStatus(jobId) for results. */
  search(params: SearchLeadsParams): Promise<SearchLeadsResponse> {
    return this.request("POST", "/lead-finder/search", params);
  }

  /** Poll a lead search job for status and partial results. */
  jobStatus(jobId: string): Promise<JobStatusResponse> {
    return this.request("GET", `/lead-finder/jobs/${jobId}`);
  }

  /** Submit positive or negative feedback on an AI-generated lead message. */
  submitFeedback(params: JobFeedbackParams): Promise<{ ok: boolean }> {
    const { jobId, ...body } = params;
    return this.request("POST", `/lead-finder/jobs/${jobId}/feedback`, body);
  }

  /** Enrich a lead via Hunter.io (person + company data). Consumes enrichment credits. */
  enrich(params: EnrichLeadParams): Promise<EnrichLeadResponse> {
    return this.request("POST", "/lead-finder/enrich", params);
  }

  /** Verify email deliverability for one or more addresses. Consumes verification credits. */
  verifyEmails(params: VerifyEmailsParams): Promise<VerifyEmailsResponse> {
    return this.request("POST", "/lead-finder/verify", params);
  }

  /** Discover companies via Hunter.io. Optionally fetch contact emails. */
  discoverCompanies(params: DiscoverCompaniesParams): Promise<DiscoverCompaniesResponse> {
    return this.request("POST", "/lead-finder/discover", params);
  }

  /** Trigger on-demand AI scoring for leads in a job or by specific lead IDs. Consumes AI credits. */
  score(params: ScoreLeadsParams): Promise<ScoreLeadsResponse> {
    return this.request("POST", "/lead-finder/score", params);
  }

  /** List Hunter.io lead lists associated with the account. */
  listLeadLists(): Promise<LeadListsResponse> {
    return this.request("GET", "/lead-finder/lists");
  }

  /** Create a new Hunter.io lead list. */
  createLeadList(name: string): Promise<{ list: LeadList }> {
    return this.request("POST", "/lead-finder/lists", { name });
  }

  /** Sync a Hunter.io lead list into local lead records. */
  syncLeadList(listId: number): Promise<SyncLeadListResponse> {
    return this.request("POST", `/lead-finder/lists/${listId}/sync`);
  }

  /** Generate a sample AI-personalised outreach message (public, no auth required). */
  previewMessage(params: PreviewMessageParams): Promise<PreviewMessageResponse> {
    return this.request("POST", "/lead-finder/preview-message", params);
  }

  /** Bulk-import selected leads into a campaign's contact list. */
  sendToCampaign(params: SendToCampaignParams): Promise<SendToCampaignResponse> {
    return this.request("POST", "/lead-finder/send-to-campaign", params);
  }
}
