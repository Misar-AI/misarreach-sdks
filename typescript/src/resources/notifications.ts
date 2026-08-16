import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export interface Notification {
  id: string;
  type: string;
  severity: "info" | "warning" | "critical";
  title: string;
  body: string | null;
  link: string | null;
  read_at: string | null;
  created_at: string;
}

export interface NotificationsResponse extends JsonObject {
  ok: boolean;
  notifications: Notification[];
  /** Counted server-side, not derived from the returned page. */
  unread: number;
  /** False when the deployment has not enabled notifications yet; the list is then empty rather than an error. */
  available?: boolean;
}

export class NotificationsResource {
  constructor(private readonly request: Requester) {}

  list(params?: { limit?: number; unreadOnly?: boolean }): Promise<NotificationsResponse> {
    const qs = new URLSearchParams();
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.unreadOnly) qs.set("unread", "1");
    const q = qs.toString();
    return this.request("GET", `/notifications${q ? `?${q}` : ""}`);
  }

  /**
   * Mark notifications read. Pass `ids` (max 250) or `{ all: true }`.
   * An empty body is rejected rather than treated as "all", so a malformed
   * request cannot silently clear the whole bell.
   */
  markRead(params: { ids?: string[]; all?: boolean }): Promise<{ ok: boolean; updated: number }> {
    return this.request("PATCH", "/notifications", params);
  }
}
