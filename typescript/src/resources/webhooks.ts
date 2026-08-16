import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

/** Events an endpoint may subscribe to. Closed set — an open one turns every internal rename into a breaking change. */
export type WebhookEvent =
  | "reply.received"
  | "deal.won"
  | "deal.lost"
  | "lead_search.completed"
  | "campaign.completed";

export interface CreateWebhookParams {
  /** HTTPS only, and must resolve to a publicly routable address. */
  url: string;
  /** At least one. There is no "everything" default, by design. */
  events: WebhookEvent[];
  description?: string;
}

export interface CreateWebhookResponse extends JsonObject {
  ok: boolean;
  endpoint: JsonObject;
  /** Returned ONCE, at creation, and never retrievable again. Store it now. */
  secret: string;
  secret_notice: string;
}

export class WebhooksResource {
  constructor(private readonly request: Requester) {}

  /** List endpoints and their delivery health. Never returns the signing secret. */
  list(): Promise<JsonObject> {
    return this.request("GET", "/webhooks/endpoints");
  }

  /**
   * Register an endpoint.
   *
   * Verify deliveries with HMAC-SHA256 over `${x-reach-timestamp}.${rawBody}`,
   * compared in constant time against `x-reach-signature`. The timestamp is
   * inside the signed string, so a captured request cannot be replayed forever.
   */
  create(params: CreateWebhookParams): Promise<CreateWebhookResponse> {
    return this.request("POST", "/webhooks/endpoints", params);
  }
}
