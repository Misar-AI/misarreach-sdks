import type { JsonObject } from "../types.js";
import {
  MisarReachError,
  errorFromPayload,
  type ErrorPayload,
} from "../errors.js";
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
  ): AsyncGenerator<LeadFinderStreamEvent, void, unknown> {
    const res = await fetch(
      `${this.baseUrl}/lead-finder/jobs/${encodeURIComponent(jobId)}/stream`,
      {
        headers: { Authorization: `Bearer ${this.apiKey}`, Accept: "text/event-stream" },
        signal: options?.signal,
      },
    );

    if (!res.ok) {
      let payload: ErrorPayload = {};
      try {
        payload = (await res.json()) as ErrorPayload;
      } catch {
        payload = { error: res.statusText };
      }
      // The same typed errors the JSON helper raises — a plan refusal on the
      // stream must not arrive as a bare Error.
      throw errorFromPayload(res.status, payload, res.statusText);
    }

    // A job that has already finished is answered with a JSON snapshot rather
    // than a stream, because there is nothing left to stream. Parsing that as
    // SSE finds no frames and completes silently, so the caller sees nothing
    // instead of the outcome. Synthesise the terminal frame the SSE path would
    // have sent, so both answers look the same to the caller.
    const contentType = res.headers.get("content-type") ?? "";
    if (!contentType.includes("text/event-stream")) {
      const snapshot = (await res.json()) as { status?: string } & Record<string, unknown>;
      yield {
        event: snapshot.status === "failed" ? "error" : "complete",
        data: snapshot,
      };
      return;
    }

    if (!res.body) throw new MisarReachError("stream had no body", res.status);

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
        for (;;) {
          const idx = frameEnd(buf);
          if (idx === -1) break;
          const frame = buf.slice(0, idx);
          buf = buf.slice(idx).replace(/^(\r?\n){1,2}/, "");
          const parsed = parseFrame(frame);
          if (parsed) yield parsed;
        }
      }
      const tail = parseFrame(buf);
      if (tail) yield tail;
    } finally {
      // Releasing the lock matters on early break: without it the response body
      // stays locked and the connection is never returned to the pool.
      reader.releaseLock();
    }
  }
}

/** One frame from the lead-finder progress stream. */
export interface LeadFinderStreamEvent {
  /**
   * The server's `event:` name. The route emits `progress`, `found`,
   * `complete`, `error` and `timeout`; `message` is the SSE default when a
   * frame carries no name.
   */
  event: string;
  data: unknown;
}

/** Index of the blank line ending the first complete frame, or -1. */
function frameEnd(buf: string): number {
  const lf = buf.indexOf("\n\n");
  const crlf = buf.indexOf("\r\n\r\n");
  if (lf === -1) return crlf;
  if (crlf === -1) return lf;
  return Math.min(lf, crlf);
}

/**
 * Parses one frame, or null for a keepalive comment or a frame with no data.
 * The route sends `: keepalive` every 20 seconds to hold the connection open.
 */
function parseFrame(frame: string): LeadFinderStreamEvent | null {
  let event = "message";
  const dataLines: string[] = [];

  for (const line of frame.split(/\r?\n/)) {
    if (!line || line.startsWith(":")) continue;
    if (line.startsWith("event:")) event = line.slice(6).trim();
    // SSE strips exactly one space after the colon, not a run of whitespace:
    // trailing spaces can be significant inside a payload.
    else if (line.startsWith("data:")) {
      const rest = line.slice(5);
      dataLines.push(rest.startsWith(" ") ? rest.slice(1) : rest);
    }
  }

  if (!dataLines.length) return null;

  const raw = dataLines.join("\n");
  try {
    return { event, data: JSON.parse(raw) };
  } catch {
    return { event, data: raw };  // a non-JSON frame is yielded as text
  }
}
