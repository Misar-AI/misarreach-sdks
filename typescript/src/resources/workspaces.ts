import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class WorkspacesResource {
  constructor(private readonly request: Requester) {}

  list(): Promise<JsonObject> {
    return this.request("GET", "/workspaces");
  }

  create(params: { name: string }): Promise<JsonObject> {
    return this.request("POST", "/workspaces", params);
  }

  members(id: string): Promise<JsonObject> {
    return this.request("GET", `/workspaces/${encodeURIComponent(id)}/members`);
  }

  addMember(id: string, params: { email: string; role?: string }): Promise<JsonObject> {
    return this.request("POST", `/workspaces/${encodeURIComponent(id)}/members`, params);
  }

  removeMember(id: string, params: { userId: string }): Promise<JsonObject> {
    return this.request("DELETE", `/workspaces/${encodeURIComponent(id)}/members`, params);
  }
}
