import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

/** Usage against one metered cap. */
export interface PlanUsageEntry {
  used: number;
  /** null means unlimited on this plan. */
  limit: number | null;
  /** null when the limit is unlimited — deliberately not 0, which would read as exhausted. */
  remaining: number | null;
  period: "month" | "total";
}

export interface PlanResponse extends JsonObject {
  plan: {
    slug: "free" | "starter" | "pro" | "scale";
    name: string;
    price_monthly: number;
    price_yearly: number | null;
  };
  limits: JsonObject;
  usage: {
    lead_searches: PlanUsageEntry;
    lead_results: PlanUsageEntry;
    autopilot_runs: PlanUsageEntry;
    pipeline_deals: PlanUsageEntry;
    linkedin_seats: PlanUsageEntry; // gitleaks:allow — field declaration, not a credential
  };
  features: {
    ai_sales_agent: boolean;
    channels: number | null;
    sequences: number | null;
  };
  /** Names of the caps with nothing left. Empty when none are spent. */
  exhausted: string[];
  /** Non-null only when something is exhausted, so its presence is the signal. */
  upgrade: { features: string[]; url: string } | null;
}

/**
 * The subscription behind the API key.
 *
 * Read this before an expensive run rather than discovering the ceiling through
 * an `UpgradeRequiredError` halfway through: a 402 tells you a call was refused,
 * whereas `usage` tells you what is left before you spend anything.
 */
export class PlanResource {
  constructor(private readonly request: Requester) {}

  /** Plan, caps, per-feature usage and the upgrade offer. */
  get(): Promise<PlanResponse> {
    return this.request("GET", "/plan");
  }
}
