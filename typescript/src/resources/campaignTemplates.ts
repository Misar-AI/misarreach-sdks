import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class CampaignTemplatesResource {
  constructor(private readonly request: Requester) {}

  /** Built-in templates (read-only) plus your own saved ones. */
  list(): Promise<JsonObject> {
    return this.request("GET", "/campaign-templates");
  }

  /** Save a template from supplied steps, or by copying an existing campaign. */
  create(params: {
    name: string;
    description?: string;
    channel?: string;
    category?: string;
    steps?: unknown[];
    fromCampaignId?: string;
  }): Promise<JsonObject> {
    return this.request("POST", "/campaign-templates", params);
  }
}
