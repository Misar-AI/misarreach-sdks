import {
  MisarReachError,
  RateLimitError,
  AuthError,
  NotFoundError,
  UpgradeRequiredError,
  errorFromPayload,
  type ErrorPayload,
} from "./errors.js";
import { LeadsResource } from "./resources/leads.js";
import { DealsResource } from "./resources/deals.js";
import { AutopilotResource } from "./resources/autopilot.js";
import { ChannelsResource } from "./resources/channels.js";
import { SalesAgentResource } from "./resources/salesAgent.js";
import { CampaignsResource } from "./resources/campaigns.js";
import { ContactsResource } from "./resources/contacts.js";
import { ConversationsResource } from "./resources/conversations.js";
import { NotificationsResource } from "./resources/notifications.js";
import { DeliverabilityResource } from "./resources/deliverability.js";
import { WebhooksResource } from "./resources/webhooks.js";
import { CampaignTemplatesResource } from "./resources/campaignTemplates.js";
import { WorkspacesResource } from "./resources/workspaces.js";
import { SettingsResource } from "./resources/settings.js";
import { AdsResource } from "./resources/ads.js";
import { LeadFinderResource } from "./resources/leadFinder.js";
import { PlanResource } from "./resources/plan.js";

export interface MisarReachClientOptions {
  /** Override the default base URL (https://api.misar.io/reach/api). */
  baseUrl?: string;
}

export class MisarReachClient {
  private readonly baseUrl: string;
  private readonly apiKey: string;

  constructor(apiKey: string, options?: MisarReachClientOptions) {
    if (!apiKey) throw new Error("MisarReachClient: apiKey is required");
    this.apiKey = apiKey;
    this.baseUrl = options?.baseUrl?.replace(/\/$/, "") ?? "https://api.misar.io/reach/api";
  }

  // ── Core request helper ──────────────────────────────────────────────────────

  async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });

    if (res.ok) return res.json() as Promise<T>;

    let payload: ErrorPayload = {};
    try {
      payload = (await res.json()) as ErrorPayload;
    } catch {
      payload = { error: res.statusText };
    }

    throw errorFromPayload(res.status, payload, res.statusText);
  }

  // ── Resource accessors ───────────────────────────────────────────────────────

  /** Live subscription standing for this key: caps, usage and the upgrade offer. */
  get plan(): PlanResource {
    return new PlanResource(this.request.bind(this));
  }

  get leads(): LeadsResource {
    return new LeadsResource(this.request.bind(this));
  }

  get deals(): DealsResource {
    return new DealsResource(this.request.bind(this));
  }

  get autopilot(): AutopilotResource {
    return new AutopilotResource(this.request.bind(this));
  }

  get channels(): ChannelsResource {
    return new ChannelsResource(this.request.bind(this));
  }

  get salesAgent(): SalesAgentResource {
    return new SalesAgentResource(this.request.bind(this));
  }

  get campaigns(): CampaignsResource {
    return new CampaignsResource(this.request.bind(this));
  }

  get contacts(): ContactsResource {
    return new ContactsResource(this.request.bind(this));
  }

  get conversations(): ConversationsResource {
    return new ConversationsResource(this.request.bind(this));
  }

  get notifications(): NotificationsResource {
    return new NotificationsResource(this.request.bind(this));
  }

  get deliverability(): DeliverabilityResource {
    return new DeliverabilityResource(this.request.bind(this));
  }

  get webhooks(): WebhooksResource {
    return new WebhooksResource(this.request.bind(this));
  }

  get campaignTemplates(): CampaignTemplatesResource {
    return new CampaignTemplatesResource(this.request.bind(this));
  }

  get workspaces(): WorkspacesResource {
    return new WorkspacesResource(this.request.bind(this));
  }

  get settings(): SettingsResource {
    return new SettingsResource(this.request.bind(this));
  }

  get ads(): AdsResource {
    return new AdsResource(this.request.bind(this));
  }

  /**
   * Lead-finder surface beyond `leads.*`. Takes baseUrl/apiKey directly as well
   * as the JSON requester, because `stream()` is Server-Sent Events and must
   * bypass the JSON helper — parsing a long-lived text stream as JSON would hang
   * until the job finished.
   */
  get leadFinder(): LeadFinderResource {
    return new LeadFinderResource(this.request.bind(this), this.baseUrl, this.apiKey);
  }
}
