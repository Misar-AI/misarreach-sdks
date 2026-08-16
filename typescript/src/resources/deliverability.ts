import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export interface SenderHealth {
  windowDays: number;
  sentTotal: number;
  delivered: number;
  bounced: number;
  complained: number;
  /** Percentage of ATTEMPTED sends. NULL means no data — NOT zero. */
  bounceRate: number | null;
  complaintRate: number | null;
  verdict: "insufficient_data" | "ok" | "watch" | "at_risk" | "critical";
}

export interface DeliverabilityResponse extends JsonObject {
  ok: boolean;
  available: boolean;
  /** Null when unavailable — deliberately not a zeroed report, which would read as healthy. */
  health: SenderHealth | null;
  advice?: string;
  thresholds?: JsonObject;
}

export class DeliverabilityResource {
  constructor(private readonly request: Requester) {}

  /**
   * Sender health for the calling account.
   *
   * Rates are over ATTEMPTED sends, matching how mailbox providers compute them.
   * The verdict encodes the Gmail/Yahoo bulk-sender rules in force since
   * February 2024: complaints at or above 0.3% is enforcement territory.
   */
  get(params?: { days?: number }): Promise<DeliverabilityResponse> {
    const q = params?.days != null ? `?days=${encodeURIComponent(String(params.days))}` : "";
    return this.request("GET", `/deliverability${q}`);
  }
}
