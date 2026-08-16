import type { JsonObject } from "../types.js";
type Requester = <T>(method: string, path: string, body?: unknown) => Promise<T>;

/**
 * The lead-finder surface beyond `leads.*` — saved searches, scoring rules,
 * company lookups, export, config and the SSE progress stream.
 */
export class LeadFinderResource {
  constructor(
    private readonly request: Requester,
    private readonly baseUrl: string,
    private readonly apiKey: string,
  ) {}

  /** Credit balance and plan allowance for lead discovery. */
  account(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/account");
  }

  /** Which of the 23 sources are enabled on this deployment. */
  config(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/config");
  }

  /** Saved leads, newest first. */
  leads(params?: { limit?: number; cursor?: string }): Promise<JsonObject> {
    const qs = new URLSearchParams();
    if (params?.limit != null) qs.set("limit", String(params.limit));
    if (params?.cursor) qs.set("cursor", params.cursor);
    const q = qs.toString();
    return this.request("GET", `/lead-finder/leads${q ? `?${q}` : ""}`);
  }

  export(params?: { format?: "csv" | "json"; jobId?: string }): Promise<JsonObject> {
    const qs = new URLSearchParams();
    if (params?.format) qs.set("format", params.format);
    if (params?.jobId) qs.set("jobId", params.jobId);
    const q = qs.toString();
    return this.request("GET", `/lead-finder/export${q ? `?${q}` : ""}`);
  }

  searchHistory(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/search-history");
  }

  recommendations(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/recommendations");
  }

  company(domain: string): Promise<JsonObject> {
    return this.request("GET", `/lead-finder/companies/${encodeURIComponent(domain)}`);
  }

  companyPeople(domain: string): Promise<JsonObject> {
    return this.request("GET", `/lead-finder/companies/${encodeURIComponent(domain)}/people`);
  }

  addToSegment(params: { leadIds: string[]; segmentId?: string; segmentName?: string }): Promise<JsonObject> {
    return this.request("POST", "/lead-finder/add-to-segment", params);
  }

  // ── saved searches ─────────────────────────────────────────────────────────
  savedSearches(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/saved-searches");
  }

  createSavedSearch(params: JsonObject): Promise<JsonObject> {
    return this.request("POST", "/lead-finder/saved-searches", params);
  }

  deleteSavedSearch(id: string): Promise<{ ok: boolean }> {
    return this.request("DELETE", `/lead-finder/saved-searches/${encodeURIComponent(id)}`);
  }

  // ── scoring rules ──────────────────────────────────────────────────────────
  scoringRules(): Promise<JsonObject> {
    return this.request("GET", "/lead-finder/scoring-rules");
  }

  createScoringRule(params: JsonObject): Promise<JsonObject> {
    return this.request("POST", "/lead-finder/scoring-rules", params);
  }

  updateScoringRule(id: string, params: JsonObject): Promise<JsonObject> {
    return this.request("PATCH", `/lead-finder/scoring-rules/${encodeURIComponent(id)}`, params);
  }

  deleteScoringRule(id: string): Promise<{ ok: boolean }> {
    return this.request("DELETE", `/lead-finder/scoring-rules/${encodeURIComponent(id)}`);
  }

  /**
   * Live progress for a running job, over Server-Sent Events.
   *
   * This is the only streaming endpoint in the API, so it does not go through
   * the JSON request helper — SSE is a long-lived text stream, and parsing it as
   * JSON would hang until the job finished.
   *
   * The returned iterator ends when the server closes the stream. Pass an
   * AbortSignal to stop early; without one, a stuck job holds the connection.
   *
   * ```ts
   * for await (const ev of reach.leadFinder.stream(jobId)) {
   *   if (ev.event === "progress") console.log(ev.data);
   * }
   * ```
   */
  async *stream(
    jobId: string,
    options?: { signal?: AbortSignal },
  ): AsyncGenerator<{ event: string; data: unknown }, void, unknown> {
    const res = await fetch(
      `${this.baseUrl}/lead-finder/jobs/${encodeURIComponent(jobId)}/stream`,
      {
        headers: { Authorization: `Bearer ${this.apiKey}`, Accept: "text/event-stream" },
        signal: options?.signal,
      },
    );
    if (!res.ok || !res.body) {
      throw new Error(`lead-finder stream failed: HTTP ${res.status}`);
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        // SSE frames are separated by a blank line; a frame can span reads, so
        // only complete frames are emitted and the remainder stays buffered.
        let idx: number;
        while ((idx = buf.indexOf("\n\n")) !== -1) {
          const frame = buf.slice(0, idx);
          buf = buf.slice(idx + 2);
          let event = "message";
          const dataLines: string[] = [];
          for (const line of frame.split("\n")) {
            if (line.startsWith("event:")) event = line.slice(6).trim();
            else if (line.startsWith("data:")) dataLines.push(line.slice(5).trim());
          }
          if (!dataLines.length) continue;
          const raw = dataLines.join("\n");
          let data: unknown = raw;
          try { data = JSON.parse(raw); } catch { /* a non-JSON frame is yielded as text */ }
          yield { event, data };
        }
      }
    } finally {
      // Releasing the lock matters on early break: without it the response body
      // stays locked and the connection is never returned to the pool.
      reader.releaseLock();
    }
  }
}
