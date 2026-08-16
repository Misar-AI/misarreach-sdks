import type {
  SalesAgentConfig,
  UpdateSalesAgentConfigParams,
  SalesAgentActionsResponse,
  ProcessSalesAgentResponse,
} from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class SalesAgentResource {
  constructor(private readonly request: Requester) {}

  /** Fetch the current user's AI sales agent configuration. */
  getConfig(): Promise<{ ok: boolean; config: SalesAgentConfig }> {
    return this.request("GET", "/sales-agent/config");
  }

  /** Update the AI sales agent configuration (partial update). */
  updateConfig(params: UpdateSalesAgentConfigParams): Promise<{ ok: boolean }> {
    return this.request("PATCH", "/sales-agent/config", params);
  }

  /** Fetch today's agent actions and summary stats. */
  getActions(): Promise<SalesAgentActionsResponse> {
    return this.request("GET", "/sales-agent/actions");
  }

  /** Run the AI sales agent pipeline on a conversation. Logs the action to the activity feed. */
  process(conversationId: string): Promise<ProcessSalesAgentResponse> {
    return this.request("POST", "/sales-agent/process", { conversationId });
  }

  /** Conversations the sales agent is handling. */
  conversations(): Promise<import("../types.js").JsonObject> {
    return this.request("GET", "/sales-agent/conversations");
  }
}
