import type { JsonObject, Paged } from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export interface CampaignStep {
  step_order: number;
  channel: string;
  delay_hours?: number;
  template: { subject?: string; body: string; variants?: unknown[] };
}

export interface CreateCampaignParams {
  name: string;
  steps?: CampaignStep[];
  scheduled_at?: string | null;
  send_interval_seconds?: number;
}

export interface EnqueueRecipient {
  email?: string | null;
  name?: string | null;
  company?: string | null;
  /** Required for SMS/WhatsApp steps — a send without an address is skipped by the consent gate. */
  phone?: string | null;
  /** Social handle, for instagram/facebook/twitter/telegram/discord steps. */
  handle?: string | null;
  linkedinUrl?: string | null;
}

export interface EnqueueResponse extends JsonObject {
  queued: number;
  skipped: number;
  recipients?: number;
  steps?: number;
  /** Channels that cannot deliver in this deployment, with the reason. Present only when some step is undeliverable. */
  warnings?: Array<{ channel: string; code: string; message: string }>;
}

export class CampaignsResource {
  constructor(private readonly request: Requester) {}

  /** List campaigns with step counts and send-status summaries. */
  list(): Promise<JsonObject> {
    return this.request("GET", "/campaigns");
  }

  /** Create a campaign, optionally with its full step sequence. */
  create(params: CreateCampaignParams): Promise<JsonObject> {
    return this.request("POST", "/campaigns", params);
  }

  get(id: string): Promise<JsonObject> {
    return this.request("GET", `/campaigns/${encodeURIComponent(id)}`);
  }

  update(id: string, params: Partial<CreateCampaignParams> & JsonObject): Promise<JsonObject> {
    return this.request("PATCH", `/campaigns/${encodeURIComponent(id)}`, params);
  }

  /**
   * Delete a campaign. With SOFT_DELETE on the row is tombstoned and its sends
   * are preserved; the response is identical either way, deliberately, so a
   * client cannot come to depend on which mode the server is in.
   */
  delete(id: string): Promise<{ ok: boolean }> {
    return this.request("DELETE", `/campaigns/${encodeURIComponent(id)}`);
  }

  /**
   * Queue recipients into a campaign's steps.
   *
   * Check `warnings` on the response: a step whose channel has no inbound path
   * in this deployment (X and Discord today) can never deliver, and the server
   * reports that here rather than silently skipping every recipient at dispatch.
   */
  enqueue(
    id: string,
    params: { recipients?: EnqueueRecipient[]; leadIds?: string[] },
  ): Promise<EnqueueResponse> {
    return this.request("POST", `/campaigns/${encodeURIComponent(id)}/enqueue`, params);
  }
}
