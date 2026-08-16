import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class AdsResource {
  constructor(private readonly request: Requester) {}

  /** Build a LinkedIn company-audience segment from a set of domains. */
  linkedInCompanyAudience(params: { domains: string[]; name?: string }): Promise<JsonObject> {
    return this.request("POST", "/ads/linkedin/company-audience", params);
  }
}
