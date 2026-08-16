import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class SettingsResource {
  constructor(private readonly request: Requester) {}

  /**
   * The CAN-SPAM sender postal address.
   * Sends are BLOCKED when this is unset — §7704(a)(5) requires a valid physical
   * address in every commercial message, so this is a prerequisite, not a nicety.
   */
  getSenderAddress(): Promise<JsonObject> {
    return this.request("GET", "/settings/sender-address");
  }

  setSenderAddress(params: { address: string }): Promise<JsonObject> {
    return this.request("PUT", "/settings/sender-address", params);
  }
}
