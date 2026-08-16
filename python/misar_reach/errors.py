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


class ReachUpgradeRequiredError(ReachAPIError):
    """429 with `upgrade: true` — plan upgrade required to proceed."""

    def __init__(self, message: str = "Upgrade required", code: str = "upgrade_required", **kw: Any):
        super().__init__(429, message, code, **kw)


class ReachNetworkError(ReachError):
    """Transport-level failure (connection reset, timeout, DNS, etc.)."""

    def __init__(self, message: str, cause: Optional[Exception] = None):
        self.cause = cause
        super().__init__(0, message, "network_error")
