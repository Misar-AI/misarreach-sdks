from __future__ import annotations

from typing import Any, Optional

__all__ = [
    "ReachError",
    "ReachAPIError",
    "ReachAuthError",
    "ReachNotFoundError",
    "ReachRateLimitError",
    "ReachUpgradeRequiredError",
    "ReachNetworkError",
]


class ReachError(Exception):
    """Base class for all MisarReach SDK errors."""

    def __init__(self, status: int, message: str, code: Optional[str] = None):
        self.status = status
        self.code = code
        super().__init__(f"misar-reach: API error {status}: {message}")


class ReachAPIError(ReachError):
    """Raised for any non-2xx response carrying the standard Error envelope."""

    def __init__(
        self,
        status: int,
        message: str,
        code: Optional[str] = None,
        error: Any = None,
        retry_after: Optional[int] = None,
    ):
        self.error = error
        self.retry_after = retry_after
        super().__init__(status, message, code)


class ReachAuthError(ReachAPIError):
    """401 / 403 — missing, invalid, or out-of-scope mrk_ key."""

    def __init__(self, message: str = "Unauthorized", code: str = "unauthorized", **kw: Any):
        super().__init__(kw.pop("status", 401), message, code, **kw)


class ReachNotFoundError(ReachAPIError):
    """404 — resource not found."""

    def __init__(self, message: str = "Not found", code: str = "not_found", **kw: Any):
        super().__init__(404, message, code, **kw)


class ReachRateLimitError(ReachAPIError):
    """429 — rate-limit tier exceeded. `retry_after` = seconds to wait."""

    def __init__(
        self,
        message: str = "Too many requests",
        code: str = "rate_limit",
        retry_after: Optional[int] = None,
        **kw: Any,
    ):
        super().__init__(429, message, code, retry_after=retry_after, **kw)


APP_ORIGIN = "https://misarreach.com"


class ReachUpgradeRequiredError(ReachAPIError):
    """A counted plan cap was hit.

    MisarReach answers 402 with ``upgrade: true`` when a cap is reached —
    searches, results, autopilot runs, deals, seats, channels — and names the
    offending counter. Retrying cannot help until the cap resets or the plan
    changes.

    Distinct from the 503 ``retry: true`` the server sends when it could not
    *check* the quota: that one is retried, so "we do not know" is never
    mistaken for "you are over your limit".

    Attributes:
        feature: The counter that was exhausted, e.g. ``lead_searches``.
        limit: The cap on the current plan.
        current: Usage against that cap when the call was refused.
        upgrade_url: Absolute URL to the billing page.
    """

    def __init__(
        self,
        message: str = "Upgrade required",
        code: str = "upgrade_required",
        status: int = 402,
        feature: Optional[str] = None,
        limit: Optional[int] = None,
        current: Optional[int] = None,
        upgrade_url: Optional[str] = None,
        **kw: Any,
    ):
        self.feature = feature
        self.limit = limit
        self.current = current
        # The server sends an app-relative path; make it linkable.
        if upgrade_url and not upgrade_url.startswith(("http://", "https://")):
            upgrade_url = APP_ORIGIN + ("" if upgrade_url.startswith("/") else "/") + upgrade_url
        self.upgrade_url = upgrade_url
        super().__init__(status, message, code, **kw)


class ReachNetworkError(ReachError):
    """Transport-level failure (connection reset, timeout, DNS, etc.)."""

    def __init__(self, message: str, cause: Optional[Exception] = None):
        self.cause = cause
        super().__init__(0, message, "network_error")
