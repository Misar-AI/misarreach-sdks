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

export class UpgradeRequiredError extends MisarReachError {
  constructor(
    message: string,
    public readonly upgrade = true,
  ) {
    super(message, 429, "upgrade_required");
    this.name = "UpgradeRequiredError";
  }
}
