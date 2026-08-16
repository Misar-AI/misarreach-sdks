import type {
  ChannelsStatusResponse,
  UpdateChannelParams,
  UpdateChannelResponse,
} from "../types.js";

type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

export class ChannelsResource {
  constructor(private readonly request: Requester) {}

  /** Get status, configuration, and delivery stats for all outreach channels (WhatsApp, SMS, push). */
  status(): Promise<ChannelsStatusResponse> {
    return this.request("GET", "/channels/status");
  }

  /** Enable or disable a specific outreach channel. */
  update(params: UpdateChannelParams): Promise<UpdateChannelResponse> {
    return this.request("PATCH", "/channels/status", params);
  }

  /** Connect a BYO Twilio number for SMS. */
  connectSms(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/sms/connect", params);
  }

  /** Connect a WhatsApp Business sender. Business-initiated sends need an approved template. */
  connectWhatsapp(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/whatsapp/connect", params);
  }

  connectInstagram(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/instagram/connect", params);
  }

  connectFacebook(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/facebook/connect", params);
  }

  connectTelegram(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/telegram/connect", params);
  }

  /**
   * Connect X. Note X is REPLY-ONLY and this deployment has no inbound path for
   * it, so the reply window can never open — see the enqueue warnings.
   */
  connectTwitter(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/twitter/connect", params);
  }

  /** Connect Discord. Reply-only; DMs arrive over the Gateway, not a webhook. */
  connectDiscord(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/discord/connect", params);
  }

  /** Register a browser push subscription. */
  subscribePush(params: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("POST", "/channels/push/subscribe", params);
  }

  unsubscribePush(params?: import("../types.js").JsonObject): Promise<import("../types.js").JsonObject> {
    return this.request("DELETE", "/channels/push/subscribe", params);
  }

  /** Double opt-in links for the channels that require a consent record. */
  optInLinks(): Promise<import("../types.js").JsonObject> {
    return this.request("GET", "/channels/opt-in-links");
  }
}
