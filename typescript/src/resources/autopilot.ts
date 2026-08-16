import type {
  StartAutopilotParams,
  StartAutopilotResponse,
  AutopilotRunsResponse,
  AutopilotStatusResponse,
} from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class AutopilotResource {
  constructor(private readonly request: Requester) {}

  /** Start a new autopilot run. Returns runId immediately; poll status() for progress. */
  start(params: StartAutopilotParams): Promise<StartAutopilotResponse> {
    return this.request("POST", "/autopilot/start", params);
  }

  /** List past autopilot runs with their status and results. */
  list(params?: { limit?: number; offset?: number }): Promise<AutopilotRunsResponse> {
    const qs = new URLSearchParams();
    if (params?.limit != null)  qs.set("limit", String(params.limit));
    if (params?.offset != null) qs.set("offset", String(params.offset));
    const query = qs.toString();
    return this.request("GET", `/autopilot/runs${query ? `?${query}` : ""}`);
  }

  /** Poll an autopilot run for its current status. */
  status(runId: string): Promise<AutopilotStatusResponse> {
    return this.request("GET", `/autopilot/${runId}/status`);
  }

  /** Stop a running autopilot run. */
  stop(runId: string): Promise<{ ok: boolean }> {
    return this.request("POST", `/autopilot/${runId}/status`, { action: "stop" });
  }

  /** Fetch a single autopilot run. */
  get(id: string): Promise<import("../types.js").JsonObject> {
    return this.request("GET", `/autopilot/${encodeURIComponent(id)}`);
  }
}
