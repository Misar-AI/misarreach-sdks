import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class ConversationsResource {
  constructor(private readonly request: Requester) {}

  /** Unified inbox: one row per contact, across every channel. */
  list(params?: { limit?: number; status?: string }): Promise<JsonObject> {
    const qs = new URLSearchParams();
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.status) qs.set("status", params.status);
    const q = qs.toString();
    return this.request("GET", `/conversations${q ? `?${q}` : ""}`);
  }

  /** One contact's full timeline across every channel. */
  get(email: string): Promise<JsonObject> {
    return this.request("GET", `/conversations/${encodeURIComponent(email)}`);
  }

  /**
   * Send a human reply into an existing thread.
   *
   * Replying is subject to the same consent gate as any other send: on a
   * REPLY_ONLY channel the recipient must have messaged first, and the window
   * may have closed. A refusal here is the gate working, not a transient error.
   */
  reply(email: string, params: { message: string; conversationId?: string }): Promise<JsonObject> {
    return this.request("POST", `/conversations/${encodeURIComponent(email)}/reply`, params);
  }
}
