export class MisarReachError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = "MisarReachError";
  }
}

export class RateLimitError extends MisarReachError {
  constructor(
    message = "Too many requests",
    public readonly balance?: number,
    public readonly freeRemaining?: number,
  ) {
    super(message, 429, "rate_limit");
    this.name = "RateLimitError";
  }
}

export class AuthError extends MisarReachError {
  constructor(message = "Unauthorized") {
    super(message, 401, "unauthorized");
    this.name = "AuthError";
  }
}

export class NotFoundError extends MisarReachError {
  constructor(message = "Not found") {
    super(message, 404, "not_found");
    this.name = "NotFoundError";
  }
}

/**
 * Thrown when the workspace's plan blocks the call.
 *
 * MisarReach answers 402 when a counted cap is hit — searches, results,
 * autopilot runs, deals, seats, channels — with `upgrade: true` and the
 * offending counter. Retrying cannot help until the cap resets or the plan
 * changes, so the client surfaces this immediately.
 *
 * Distinct from the 503 `retry: true` the server sends when it could not
 * *check* the quota: that one is retried, deliberately, so "we don't know" is
 * never mistaken for "you're over your limit".
 */
export class UpgradeRequiredError extends MisarReachError {
  constructor(
    message: string,
    /** HTTP status — 402 in practice; 429 accepted for older deployments. */
    status = 402,
    /** The counter that was exhausted, e.g. `lead_searches`. */
    public readonly feature?: string,
    /** The cap on the current plan. */
    public readonly limit?: number,
    /** Usage against that cap when the call was refused. */
    public readonly current?: number,
    /** Absolute URL to the billing page. */
    public readonly upgradeUrl?: string,
    public readonly upgrade = true,
  ) {
    super(message, status, "upgrade_required");
    this.name = "UpgradeRequiredError";
  }
}

/** The error envelope MisarReach returns on a non-2xx. */
export interface ErrorPayload {
  error?: string;
  balance?: number;
  freeRemaining?: number;
  upgrade?: boolean;
  feature?: string;
  limit?: number;
  current?: number;
  upgrade_url?: string;
}

/**
 * The server returns `upgrade_url` as an app-relative path
 * (`/settings?tab=billing`). Resolve it against the app origin so callers can
 * link to it directly.
 */
export function absoluteUpgradeUrl(path?: string): string | undefined {
  if (!path) return undefined;
  if (/^https?:\/\//.test(path)) return path;
  return `https://misarreach.com${path.startsWith("/") ? path : `/${path}`}`;
}

/**
 * Maps a refused response onto the typed error for it.
 *
 * Shared by the JSON request helper and the SSE stream: a plan refusal must
 * surface identically whichever one the caller reached for, and duplicating the
 * `upgrade: true` check is how the two drift apart.
 */
export function errorFromPayload(
  status: number,
  payload: ErrorPayload,
  statusText = "",
): MisarReachError {
  const msg = payload.error ?? statusText;

  // A plan refusal arrives as 402 with `upgrade: true`. 429 is still accepted
  // in case an older deployment answers with it.
  if (payload.upgrade === true && (status === 402 || status === 429)) {
    return new UpgradeRequiredError(
      msg,
      status,
      payload.feature,
      payload.limit,
      payload.current,
      absoluteUpgradeUrl(payload.upgrade_url),
    );
  }

  switch (status) {
    case 401:
    case 403:
      return new AuthError(msg);
    case 404:
      return new NotFoundError(msg);
    case 429:
      return new RateLimitError(msg, payload.balance, payload.freeRemaining);
    default:
      return new MisarReachError(msg, status);
  }
}
