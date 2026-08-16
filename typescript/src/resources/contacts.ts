import type { JsonObject } from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export interface ConsentEvidence {
  /** Where consent was collected, e.g. "signup form /pricing". */
  source: string;
  /** ISO-8601 timestamp of when it was given. */
  timestamp: string;
  evidence?: JsonObject;
}

export interface ContactInput {
  email: string;
  firstName?: string | null;
  lastName?: string | null;
  phone?: string | null;
  company?: string | null;
  jobTitle?: string | null;
  status?: "subscribed" | "unsubscribed" | "bounced" | "complained";
  /** Per-contact consent evidence; overrides the batch `defaultConsent`. */
  consent?: ConsentEvidence;
}

export class ContactsResource {
  constructor(private readonly request: Requester) {}

  list(params?: { limit?: number; offset?: number; status?: string }): Promise<JsonObject> {
    const qs = new URLSearchParams();
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.offset != null) qs.set("offset", String(params.offset));
    if (params?.status) qs.set("status", params.status);
    const q = qs.toString();
    return this.request("GET", `/contacts${q ? `?${q}` : ""}`);
  }

  create(contact: ContactInput): Promise<JsonObject> {
    return this.request("POST", "/contacts", contact);
  }

  get(id: string): Promise<JsonObject> {
    return this.request("GET", `/contacts/${encodeURIComponent(id)}`);
  }

  update(id: string, patch: Partial<ContactInput>): Promise<JsonObject> {
    return this.request("PATCH", `/contacts/${encodeURIComponent(id)}`, patch);
  }

  delete(id: string): Promise<JsonObject> {
    return this.request("DELETE", `/contacts/${encodeURIComponent(id)}`);
  }

  stats(): Promise<JsonObject> {
    return this.request("GET", "/contacts/stats");
  }

  segments(): Promise<JsonObject> {
    return this.request("GET", "/contacts/segments");
  }

  /** Bulk delete / unsubscribe / resubscribe. Max 500 ids per call. */
  bulk(params: { action: "delete" | "unsubscribe" | "resubscribe"; ids: string[] }): Promise<JsonObject> {
    return this.request("POST", "/contacts/bulk", params);
  }

  /**
   * Import up to 5000 contacts.
   *
   * A contact may only be imported as `subscribed` WITH consent evidence — per
   * contact, or via `defaultConsent`. Without it the server coerces the status
   * so no channel treats the contact as opted in, because "it was in the list we
   * bought" is not consent under TCPA, CASL or GDPR.
   */
  import(params: { contacts: ContactInput[]; defaultConsent?: ConsentEvidence }): Promise<JsonObject> {
    return this.request("POST", "/contacts/import", params);
  }
}
