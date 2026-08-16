import type {
  ListDealsParams,
  ListDealsResponse,
  CreateDealParams,
  CreateDealResponse,
  UpdateDealParams,
  UpdateDealResponse,
  PipelineResponse,
  MoveDealParams,
  MoveDealResponse,
} from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class DealsResource {
  constructor(private readonly request: Requester) {}

  /**
   * List deals with optional status filter and pagination.
   */
  list(params?: ListDealsParams): Promise<ListDealsResponse> {
    const qs = new URLSearchParams();
    if (params?.status) qs.set("status", params.status);
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.offset != null) qs.set("offset", String(params.offset));
    const query = qs.toString();
    return this.request("GET", `/deals${query ? `?${query}` : ""}`);
  }

  /**
   * Create a new deal (optionally linked to a conversation or campaign).
   */
  create(params: CreateDealParams): Promise<CreateDealResponse> {
    return this.request("POST", "/deals", params);
  }

  /**
   * Update deal status, value, or notes.
   */
  update(id: string, params: UpdateDealParams): Promise<UpdateDealResponse> {
    return this.request("PATCH", `/deals/${id}`, params);
  }

  /**
   * Get the Kanban pipeline board grouped by stage.
   */
  pipeline(workspaceId?: string): Promise<PipelineResponse> {
    const qs = workspaceId ? `?workspaceId=${encodeURIComponent(workspaceId)}` : "";
    return this.request("GET", `/pipeline${qs}`);
  }

  /**
   * Move a deal to a new stage (drag-and-drop).
   */
  movePipelineStage(params: MoveDealParams): Promise<MoveDealResponse> {
    return this.request("POST", "/pipeline", params);
  }

  /** Activity log for a deal. */
  activity(id: string): Promise<import("../types.js").JsonObject> {
    return this.request("GET", `/deals/${encodeURIComponent(id)}/activity`);
  }

  /** AI next-step suggestions for a deal. */
  suggestions(id: string): Promise<import("../types.js").JsonObject> {
    return this.request("GET", `/deals/${encodeURIComponent(id)}/suggestions`);
  }

  /**
   * Bulk delete / move / tag a selection (max 250 ids).
   *
   * `matched` is what ACTUALLY changed and need not equal `requested` — ids
   * belonging to another account are skipped rather than erroring. Compare the
   * two before reporting success to a user.
   */
  bulk(params: {
    action: "delete" | "move" | "tag";
    ids: string[];
    stage?: string;
    add?: string[];
    remove?: string[];
  }): Promise<{ ok: boolean; action: string; requested: number; matched: number }> {
    return this.request("POST", "/deals/bulk", params);
  }
}
