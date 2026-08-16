from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass
from typing import Any, AsyncIterator, Iterator, Optional
from urllib.parse import quote

import httpx

from .errors import (
    ReachAPIError,
    ReachAuthError,
    ReachError,
    ReachNetworkError,
    ReachNotFoundError,
    ReachRateLimitError,
    ReachUpgradeRequiredError,
)

__all__ = ["MisarReachClient", "SSEEvent"]

DEFAULT_BASE_URL = "https://api.misar.io/reach/api"
RETRY_BASE_S = 0.2
RETRYABLE = {429, 500, 502, 503, 504}


def _clean(d: Optional[dict]) -> Optional[dict]:
    if d is None:
        return None
    return {k: v for k, v in d.items() if v is not None}


@dataclass
class SSEEvent:
    """A single Server-Sent Event from the lead-finder job stream."""

    event: str
    data: Any


def _raise_for_error(status: int, payload: dict) -> None:
    err = payload.get("error")
    msg = err if isinstance(err, str) else (payload.get("message") or "unknown error")
    code = payload.get("code")
    retry_after = payload.get("retryAfter")
    if status in (401, 403):
        raise ReachAuthError(msg, code or "unauthorized", error=err, status=status)
    if status == 404:
        raise ReachNotFoundError(msg, code or "not_found", error=err)
    if status == 429:
        if payload.get("upgrade"):
            raise ReachUpgradeRequiredError(msg, code or "upgrade_required", error=err)
        raise ReachRateLimitError(msg, code or "rate_limit", retry_after=retry_after, error=err)
    raise ReachAPIError(status, msg, code, error=err, retry_after=retry_after)


class _ReachCore:
    _api_key: str
    _base_url: str
    _max_retries: int
    _timeout: float

    # ── Sync ────────────────────────────────────────────────────────────────────

    def _request(
        self,
        method: str,
        path: str,
        body: Optional[dict] = None,
        *,
        params: Optional[dict] = None,
    ) -> Any:
        url = self._base_url + path
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        last_exc: Optional[Exception] = None
        for attempt in range(self._max_retries):
            try:
                resp = httpx.request(
                    method,
                    url,
                    headers=headers,
                    params=_clean(params),
                    json=body,
                    timeout=self._timeout,
                )
                status = resp.status_code
                if status in RETRYABLE and attempt < self._max_retries - 1:
                    time.sleep(RETRY_BASE_S * (2**attempt))
                    continue
                if not resp.is_success:
                    data = resp.json() if resp.content else {}
                    _raise_for_error(status, data if isinstance(data, dict) else {"error": str(data)})
                return resp.json() if resp.content else {}
            except ReachError:
                raise
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                if attempt < self._max_retries - 1:
                    time.sleep(RETRY_BASE_S * (2**attempt))
                    continue
                raise ReachNetworkError(str(exc), exc) from exc
        raise ReachNetworkError("max retries exceeded", last_exc)

    async def _arequest(
        self,
        method: str,
        path: str,
        body: Optional[dict] = None,
        *,
        params: Optional[dict] = None,
    ) -> Any:
        url = self._base_url + path
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        last_exc: Optional[Exception] = None
        async with httpx.AsyncClient(timeout=self._timeout) as http:
            for attempt in range(self._max_retries):
                try:
                    resp = await http.request(
                        method,
                        url,
                        headers=headers,
                        params=_clean(params),
                        json=body,
                    )
                    status = resp.status_code
                    if status in RETRYABLE and attempt < self._max_retries - 1:
                        await asyncio.sleep(RETRY_BASE_S * (2**attempt))
                        continue
                    if not resp.is_success:
                        data = resp.json() if resp.content else {}
                        _raise_for_error(status, data if isinstance(data, dict) else {"error": str(data)})
                    return resp.json() if resp.content else {}
                except ReachError:
                    raise
                except Exception as exc:  # noqa: BLE001
                    last_exc = exc
                    if attempt < self._max_retries - 1:
                        await asyncio.sleep(RETRY_BASE_S * (2**attempt))
                        continue
                    raise ReachNetworkError(str(exc), exc) from exc
        raise ReachNetworkError("max retries exceeded", last_exc)

    # ── SSE ─────────────────────────────────────────────────────────────────────

    @staticmethod
    def _parse_sse_block(block: str) -> Optional[SSEEvent]:
        event = "message"
        data_lines: list[str] = []
        for line in block.splitlines():
            if line.startswith("event:"):
                event = line[len("event:"):].strip()
            elif line.startswith("data:"):
                data_lines.append(line[len("data:"):].strip())
        if not data_lines:
            return None
        raw = "\n".join(data_lines)
        try:
            data: Any = json.loads(raw)
        except json.JSONDecodeError:
            data = raw
        return SSEEvent(event=event, data=data)

    def _stream(self, path: str, *, params: Optional[dict] = None) -> Iterator[SSEEvent]:
        url = self._base_url + path
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Accept": "text/event-stream",
        }
        with httpx.stream(
            "GET", url, headers=headers, params=_clean(params), timeout=None
        ) as resp:
            if not resp.is_success:
                resp.read()
                data = resp.json() if resp.content else {}
                _raise_for_error(resp.status_code, data if isinstance(data, dict) else {"error": str(data)})
            # If the job is already finished the server returns a plain JSON snapshot.
            if "text/event-stream" not in resp.headers.get("content-type", ""):
                resp.read()
                yield SSEEvent(event="complete", data=resp.json() if resp.content else {})
                return
            buffer = ""
            for chunk in resp.iter_text():
                buffer += chunk
                while "\n\n" in buffer:
                    block, buffer = buffer.split("\n\n", 1)
                    evt = self._parse_sse_block(block)
                    if evt is not None:
                        yield evt

    async def _astream(self, path: str, *, params: Optional[dict] = None) -> AsyncIterator[SSEEvent]:
        url = self._base_url + path
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Accept": "text/event-stream",
        }
        async with httpx.AsyncClient(timeout=None) as http:
            async with http.stream("GET", url, headers=headers, params=_clean(params)) as resp:
                if not resp.is_success:
                    await resp.aread()
                    data = resp.json() if resp.content else {}
                    _raise_for_error(resp.status_code, data if isinstance(data, dict) else {"error": str(data)})
                if "text/event-stream" not in resp.headers.get("content-type", ""):
                    await resp.aread()
                    yield SSEEvent(event="complete", data=resp.json() if resp.content else {})
                    return
                buffer = ""
                async for chunk in resp.aiter_text():
                    buffer += chunk
                    while "\n\n" in buffer:
                        block, buffer = buffer.split("\n\n", 1)
                        evt = self._parse_sse_block(block)
                        if evt is not None:
                            yield evt


class _Resource:
    def __init__(self, client: _ReachCore) -> None:
        self._c = client


# ── Lead Finder ──────────────────────────────────────────────────────────────────

class _LeadsResource(_Resource):
    """Lead Finder — search (23 sources), discover, enrich, verify, score, lists,
    saved searches, scoring rules, recommendations, and the SSE job stream."""

    def account(self) -> Any:
        return self._c._request("GET", "/lead-finder/account")

    async def aaccount(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/account")

    def config(self) -> Any:
        return self._c._request("GET", "/lead-finder/config")

    async def aconfig(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/config")

    def list(self, **params: Any) -> Any:
        return self._c._request("GET", "/lead-finder/leads", params=params or None)

    async def alist(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/lead-finder/leads", params=params or None)

    def search(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/search", data)

    async def asearch(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/search", data)

    def discover(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/discover", data)

    async def adiscover(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/discover", data)

    def enrich(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/enrich", data)

    async def aenrich(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/enrich", data)

    def verify(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/verify", data)

    async def averify(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/verify", data)

    def score(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/score", data)

    async def ascore(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/score", data)

    def export(self, **params: Any) -> Any:
        return self._c._request("GET", "/lead-finder/export", params=params or None)

    async def aexport(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/lead-finder/export", params=params or None)

    def get_job(self, job_id: str) -> Any:
        return self._c._request("GET", f"/lead-finder/jobs/{quote(job_id, safe='')}")

    async def aget_job(self, job_id: str) -> Any:
        return await self._c._arequest("GET", f"/lead-finder/jobs/{quote(job_id, safe='')}")

    def submit_feedback(self, job_id: str, data: dict[str, Any]) -> Any:
        return self._c._request("POST", f"/lead-finder/jobs/{quote(job_id, safe='')}/feedback", data)

    async def asubmit_feedback(self, job_id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", f"/lead-finder/jobs/{quote(job_id, safe='')}/feedback", data)

    def stream_job(self, job_id: str) -> Iterator[SSEEvent]:
        """Consume the lead-finder job SSE stream (sync generator).

        Yields ``SSEEvent(event, data)``: ``progress`` events with
        ``{message, total_found}`` then a terminal ``complete`` or ``error``.
        If the job is already finished a single ``complete`` snapshot is yielded.
        """
        return self._c._stream(f"/lead-finder/jobs/{quote(job_id, safe='')}/stream")

    def astream_job(self, job_id: str) -> AsyncIterator[SSEEvent]:
        """Consume the lead-finder job SSE stream (async generator)."""
        return self._c._astream(f"/lead-finder/jobs/{quote(job_id, safe='')}/stream")

    def search_history(self) -> Any:
        return self._c._request("GET", "/lead-finder/search-history")

    async def asearch_history(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/search-history")

    def recommendations(self) -> Any:
        return self._c._request("GET", "/lead-finder/recommendations")

    async def arecommendations(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/recommendations")

    def preview_message(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/preview-message", data)

    async def apreview_message(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/preview-message", data)

    def send_to_campaign(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/send-to-campaign", data)

    async def asend_to_campaign(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/send-to-campaign", data)

    def add_to_segment(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/add-to-segment", data)

    async def aadd_to_segment(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/add-to-segment", data)

    def company(self, domain: str) -> Any:
        return self._c._request("GET", f"/lead-finder/companies/{quote(domain, safe='')}")

    async def acompany(self, domain: str) -> Any:
        return await self._c._arequest("GET", f"/lead-finder/companies/{quote(domain, safe='')}")

    def company_people(self, domain: str) -> Any:
        return self._c._request("GET", f"/lead-finder/companies/{quote(domain, safe='')}/people")

    async def acompany_people(self, domain: str) -> Any:
        return await self._c._arequest("GET", f"/lead-finder/companies/{quote(domain, safe='')}/people")

    # ── Lists ────────────────────────────────────────────────────────────────────

    def lists(self) -> Any:
        return self._c._request("GET", "/lead-finder/lists")

    async def alists(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/lists")

    def create_list(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/lists", data)

    async def acreate_list(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/lists", data)

    def sync_list(self, list_id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return self._c._request("POST", f"/lead-finder/lists/{quote(str(list_id), safe='')}/sync", data or {})

    async def async_list(self, list_id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return await self._c._arequest("POST", f"/lead-finder/lists/{quote(str(list_id), safe='')}/sync", data or {})

    # ── Saved searches ───────────────────────────────────────────────────────────

    def saved_searches(self) -> Any:
        return self._c._request("GET", "/lead-finder/saved-searches")

    async def asaved_searches(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/saved-searches")

    def create_saved_search(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/saved-searches", data)

    async def acreate_saved_search(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/saved-searches", data)

    def delete_saved_search(self, id: str) -> Any:
        return self._c._request("DELETE", f"/lead-finder/saved-searches/{quote(str(id), safe='')}")

    async def adelete_saved_search(self, id: str) -> Any:
        return await self._c._arequest("DELETE", f"/lead-finder/saved-searches/{quote(str(id), safe='')}")

    # ── Scoring rules ────────────────────────────────────────────────────────────

    def scoring_rules(self) -> Any:
        return self._c._request("GET", "/lead-finder/scoring-rules")

    async def ascoring_rules(self) -> Any:
        return await self._c._arequest("GET", "/lead-finder/scoring-rules")

    def create_scoring_rule(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/lead-finder/scoring-rules", data)

    async def acreate_scoring_rule(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/lead-finder/scoring-rules", data)

    def update_scoring_rule(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", f"/lead-finder/scoring-rules/{quote(str(id), safe='')}", data)

    async def aupdate_scoring_rule(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", f"/lead-finder/scoring-rules/{quote(str(id), safe='')}", data)

    def delete_scoring_rule(self, id: str) -> Any:
        return self._c._request("DELETE", f"/lead-finder/scoring-rules/{quote(str(id), safe='')}")

    async def adelete_scoring_rule(self, id: str) -> Any:
        return await self._c._arequest("DELETE", f"/lead-finder/scoring-rules/{quote(str(id), safe='')}")


# ── Deals + Pipeline ─────────────────────────────────────────────────────────────

class _DealsResource(_Resource):
    def list(self, **params: Any) -> Any:
        return self._c._request("GET", "/deals", params=params or None)

    async def alist(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/deals", params=params or None)

    def create(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/deals", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/deals", data)

    def update(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", f"/deals/{quote(str(id), safe='')}", data)

    async def aupdate(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", f"/deals/{quote(str(id), safe='')}", data)

    def delete(self, id: str) -> Any:
        return self._c._request("DELETE", f"/deals/{quote(str(id), safe='')}")

    async def adelete(self, id: str) -> Any:
        return await self._c._arequest("DELETE", f"/deals/{quote(str(id), safe='')}")

    def activity(self, id: str) -> Any:
        return self._c._request("GET", f"/deals/{quote(str(id), safe='')}/activity")

    async def aactivity(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/deals/{quote(str(id), safe='')}/activity")

    def suggestions(self, id: str) -> Any:
        return self._c._request("GET", f"/deals/{quote(str(id), safe='')}/suggestions")

    async def asuggestions(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/deals/{quote(str(id), safe='')}/suggestions")

    def bulk(self, data: dict[str, Any]) -> Any:
        """Apply one operation to many deals at once — ``{"ids": [...], "op":
        "tag"|"untag"|"stage"|"delete", ...}``. Tag writes are applied
        atomically server-side, so concurrent callers cannot lose a tag."""
        return self._c._request("POST", "/deals/bulk", data)

    async def abulk(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/deals/bulk", data)


class _PipelineResource(_Resource):
    def get(self) -> Any:
        return self._c._request("GET", "/pipeline")

    async def aget(self) -> Any:
        return await self._c._arequest("GET", "/pipeline")

    def move(self, data: dict[str, Any]) -> Any:
        """Move a deal to a new pipeline stage (drag-and-drop equivalent)."""
        return self._c._request("POST", "/pipeline", data)

    async def amove(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/pipeline", data)


# ── Channels ─────────────────────────────────────────────────────────────────────

_CHANNEL_CONNECTORS = ("whatsapp", "sms", "telegram", "twitter", "instagram", "facebook", "discord")


class _ChannelsResource(_Resource):
    def status(self) -> Any:
        return self._c._request("GET", "/channels/status")

    async def astatus(self) -> Any:
        return await self._c._arequest("GET", "/channels/status")

    def update_status(self, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", "/channels/status", data)

    async def aupdate_status(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", "/channels/status", data)

    def opt_in_links(self) -> Any:
        return self._c._request("GET", "/channels/opt-in-links")

    async def aopt_in_links(self) -> Any:
        return await self._c._arequest("GET", "/channels/opt-in-links")

    def connect(self, channel: str, data: dict[str, Any]) -> Any:
        """Connect one channel. `channel` in whatsapp|sms|telegram|twitter|instagram|facebook|discord."""
        if channel not in _CHANNEL_CONNECTORS:
            raise ValueError(f"unknown channel {channel!r}; expected one of {_CHANNEL_CONNECTORS}")
        return self._c._request("POST", f"/channels/{channel}/connect", data)

    async def aconnect(self, channel: str, data: dict[str, Any]) -> Any:
        if channel not in _CHANNEL_CONNECTORS:
            raise ValueError(f"unknown channel {channel!r}; expected one of {_CHANNEL_CONNECTORS}")
        return await self._c._arequest("POST", f"/channels/{channel}/connect", data)

    def push_subscribe(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/channels/push/subscribe", data)

    async def apush_subscribe(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/channels/push/subscribe", data)

    def push_unsubscribe(self) -> Any:
        return self._c._request("DELETE", "/channels/push/subscribe")

    async def apush_unsubscribe(self) -> Any:
        return await self._c._arequest("DELETE", "/channels/push/subscribe")


# ── Autopilot ────────────────────────────────────────────────────────────────────

class _AutopilotResource(_Resource):
    def start(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/autopilot/start", data)

    async def astart(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/autopilot/start", data)

    def runs(self, **params: Any) -> Any:
        return self._c._request("GET", "/autopilot/runs", params=params or None)

    async def aruns(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/autopilot/runs", params=params or None)

    def get(self, id: str) -> Any:
        return self._c._request("GET", f"/autopilot/{quote(str(id), safe='')}")

    async def aget(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/autopilot/{quote(str(id), safe='')}")

    def status(self, id: str) -> Any:
        return self._c._request("GET", f"/autopilot/{quote(str(id), safe='')}/status")

    async def astatus(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/autopilot/{quote(str(id), safe='')}/status")

    def set_status(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("POST", f"/autopilot/{quote(str(id), safe='')}/status", data)

    async def aset_status(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", f"/autopilot/{quote(str(id), safe='')}/status", data)


# ── Sales Agent ──────────────────────────────────────────────────────────────────

class _SalesAgentResource(_Resource):
    def config(self) -> Any:
        return self._c._request("GET", "/sales-agent/config")

    async def aconfig(self) -> Any:
        return await self._c._arequest("GET", "/sales-agent/config")

    def update_config(self, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", "/sales-agent/config", data)

    async def aupdate_config(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", "/sales-agent/config", data)

    def actions(self, **params: Any) -> Any:
        return self._c._request("GET", "/sales-agent/actions", params=params or None)

    async def aactions(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/sales-agent/actions", params=params or None)

    def conversations(self, **params: Any) -> Any:
        return self._c._request("GET", "/sales-agent/conversations", params=params or None)

    async def aconversations(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/sales-agent/conversations", params=params or None)

    def process(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/sales-agent/process", data)

    async def aprocess(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/sales-agent/process", data)


# ── Campaigns ────────────────────────────────────────────────────────────────────

class _CampaignsResource(_Resource):
    def list(self, **params: Any) -> Any:
        return self._c._request("GET", "/campaigns", params=params or None)

    async def alist(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/campaigns", params=params or None)

    def create(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/campaigns", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/campaigns", data)

    def get(self, id: str) -> Any:
        return self._c._request("GET", f"/campaigns/{quote(str(id), safe='')}")

    async def aget(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/campaigns/{quote(str(id), safe='')}")

    def update(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", f"/campaigns/{quote(str(id), safe='')}", data)

    async def aupdate(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", f"/campaigns/{quote(str(id), safe='')}", data)

    def delete(self, id: str) -> Any:
        return self._c._request("DELETE", f"/campaigns/{quote(str(id), safe='')}")

    async def adelete(self, id: str) -> Any:
        return await self._c._arequest("DELETE", f"/campaigns/{quote(str(id), safe='')}")

    def enqueue(self, id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return self._c._request("POST", f"/campaigns/{quote(str(id), safe='')}/enqueue", data or {})

    async def aenqueue(self, id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return await self._c._arequest("POST", f"/campaigns/{quote(str(id), safe='')}/enqueue", data or {})


# ── Contacts + Segments ──────────────────────────────────────────────────────────

class _ContactsResource(_Resource):
    def list(self, **params: Any) -> Any:
        return self._c._request("GET", "/contacts", params=params or None)

    async def alist(self, **params: Any) -> Any:
        return await self._c._arequest("GET", "/contacts", params=params or None)

    def create(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/contacts", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/contacts", data)

    def get(self, id: str) -> Any:
        return self._c._request("GET", f"/contacts/{quote(str(id), safe='')}")

    async def aget(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/contacts/{quote(str(id), safe='')}")

    def update(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("PATCH", f"/contacts/{quote(str(id), safe='')}", data)

    async def aupdate(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", f"/contacts/{quote(str(id), safe='')}", data)

    def delete(self, id: str) -> Any:
        return self._c._request("DELETE", f"/contacts/{quote(str(id), safe='')}")

    async def adelete(self, id: str) -> Any:
        return await self._c._arequest("DELETE", f"/contacts/{quote(str(id), safe='')}")

    def bulk(self, data: dict[str, Any]) -> Any:
        """Bulk action over contact ids, e.g. {"action": "delete", "ids": [...]}."""
        return self._c._request("POST", "/contacts/bulk", data)

    async def abulk(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/contacts/bulk", data)

    def import_contacts(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/contacts/import", data)

    async def aimport_contacts(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/contacts/import", data)

    def segments(self) -> Any:
        return self._c._request("GET", "/contacts/segments")

    async def asegments(self) -> Any:
        return await self._c._arequest("GET", "/contacts/segments")

    def stats(self) -> Any:
        return self._c._request("GET", "/contacts/stats")

    async def astats(self) -> Any:
        return await self._c._arequest("GET", "/contacts/stats")


# ── Conversations ────────────────────────────────────────────────────────────────

class _ConversationsResource(_Resource):
    def list(
        self,
        status: Optional[str] = None,
        channel: Optional[str] = None,
        q: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> Any:
        return self._c._request(
            "GET", "/conversations",
            params={"status": status, "channel": channel, "q": q, "limit": limit},
        )

    async def alist(
        self,
        status: Optional[str] = None,
        channel: Optional[str] = None,
        q: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> Any:
        return await self._c._arequest(
            "GET", "/conversations",
            params={"status": status, "channel": channel, "q": q, "limit": limit},
        )

    def get(self, email: str) -> Any:
        return self._c._request("GET", f"/conversations/{quote(email, safe='')}")

    async def aget(self, email: str) -> Any:
        return await self._c._arequest("GET", f"/conversations/{quote(email, safe='')}")

    def reply(self, email: str, data: dict[str, Any]) -> Any:
        return self._c._request("POST", f"/conversations/{quote(email, safe='')}/reply", data)

    async def areply(self, email: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", f"/conversations/{quote(email, safe='')}/reply", data)


# ── Campaign templates ───────────────────────────────────────────────────────────

class _CampaignTemplatesResource(_Resource):
    def list(self, category: Optional[str] = None) -> Any:
        return self._c._request("GET", "/campaign-templates", params={"category": category})

    async def alist(self, category: Optional[str] = None) -> Any:
        return await self._c._arequest("GET", "/campaign-templates", params={"category": category})

    def create(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/campaign-templates", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/campaign-templates", data)


# ── Deliverability ───────────────────────────────────────────────────────────────

class _DeliverabilityResource(_Resource):
    def get(self, days: Optional[int] = None) -> Any:
        """Sender health. ``bounceRate``/``complaintRate`` are None when there is
        not enough volume to judge — that is not the same as zero."""
        return self._c._request("GET", "/deliverability", params={"days": days})

    async def aget(self, days: Optional[int] = None) -> Any:
        return await self._c._arequest("GET", "/deliverability", params={"days": days})


# ── Notifications ────────────────────────────────────────────────────────────────

class _NotificationsResource(_Resource):
    def list(self, unread_only: Optional[bool] = None, limit: Optional[int] = None) -> Any:
        return self._c._request(
            "GET", "/notifications",
            params={"unreadOnly": unread_only, "limit": limit},
        )

    async def alist(self, unread_only: Optional[bool] = None, limit: Optional[int] = None) -> Any:
        return await self._c._arequest(
            "GET", "/notifications",
            params={"unreadOnly": unread_only, "limit": limit},
        )

    def mark_read(self, data: dict[str, Any]) -> Any:
        """Mark notifications read. Pass ``{"ids": [...]}`` or ``{"all": True}``."""
        return self._c._request("PATCH", "/notifications", data)

    async def amark_read(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PATCH", "/notifications", data)


# ── Webhooks ─────────────────────────────────────────────────────────────────────

class _WebhooksResource(_Resource):
    def list(self) -> Any:
        return self._c._request("GET", "/webhooks/endpoints")

    async def alist(self) -> Any:
        return await self._c._arequest("GET", "/webhooks/endpoints")

    def create(self, data: dict[str, Any]) -> Any:
        """Register an endpoint. The response carries the signing secret exactly
        once — store it then; it is not retrievable afterwards."""
        return self._c._request("POST", "/webhooks/endpoints", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/webhooks/endpoints", data)


# ── Settings ─────────────────────────────────────────────────────────────────────

class _SettingsResource(_Resource):
    def sender_address(self) -> Any:
        return self._c._request("GET", "/settings/sender-address")

    async def asender_address(self) -> Any:
        return await self._c._arequest("GET", "/settings/sender-address")

    def set_sender_address(self, data: dict[str, Any]) -> Any:
        return self._c._request("PUT", "/settings/sender-address", data)

    async def aset_sender_address(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("PUT", "/settings/sender-address", data)


# ── Workspaces ───────────────────────────────────────────────────────────────────

class _WorkspacesResource(_Resource):
    def list(self) -> Any:
        return self._c._request("GET", "/workspaces")

    async def alist(self) -> Any:
        return await self._c._arequest("GET", "/workspaces")

    def create(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/workspaces", data)

    async def acreate(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/workspaces", data)

    def members(self, id: str) -> Any:
        return self._c._request("GET", f"/workspaces/{quote(str(id), safe='')}/members")

    async def amembers(self, id: str) -> Any:
        return await self._c._arequest("GET", f"/workspaces/{quote(str(id), safe='')}/members")

    def add_member(self, id: str, data: dict[str, Any]) -> Any:
        return self._c._request("POST", f"/workspaces/{quote(str(id), safe='')}/members", data)

    async def aadd_member(self, id: str, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", f"/workspaces/{quote(str(id), safe='')}/members", data)

    def remove_member(self, id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return self._c._request("DELETE", f"/workspaces/{quote(str(id), safe='')}/members", data)

    async def aremove_member(self, id: str, data: Optional[dict[str, Any]] = None) -> Any:
        return await self._c._arequest("DELETE", f"/workspaces/{quote(str(id), safe='')}/members", data)


# ── Ads ──────────────────────────────────────────────────────────────────────────

class _AdsResource(_Resource):
    def linkedin_company_audience(self, data: dict[str, Any]) -> Any:
        return self._c._request("POST", "/ads/linkedin/company-audience", data)

    async def alinkedin_company_audience(self, data: dict[str, Any]) -> Any:
        return await self._c._arequest("POST", "/ads/linkedin/company-audience", data)


# ── Main Client ──────────────────────────────────────────────────────────────────

class MisarReachClient(_ReachCore):
    """
    MisarReach Developer API client — sync and async.

    Auth: a reach developer key (``mrk_...``). It is validated only against the
    reach-owned key table, so a key from any other Misar product is rejected.

    Sync usage:
        client = MisarReachClient("mrk_...")
        client.leads.search({"query": "SaaS founders in Berlin", "useAI": True})
        client.deals.list()

    Async usage:
        client = MisarReachClient("mrk_...")
        await client.leads.asearch({"query": "..."})

    Streaming a lead-finder job:
        for evt in client.leads.stream_job(job_id):
            print(evt.event, evt.data)
    """

    def __init__(
        self,
        api_key: str,
        base_url: str = DEFAULT_BASE_URL,
        max_retries: int = 3,
        timeout: float = 30.0,
    ) -> None:
        if not api_key:
            raise ValueError("MisarReachClient: api_key is required")
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._max_retries = max_retries
        self._timeout = timeout

        self.leads = _LeadsResource(self)
        self.deals = _DealsResource(self)
        self.pipeline = _PipelineResource(self)
        self.channels = _ChannelsResource(self)
        self.autopilot = _AutopilotResource(self)
        self.sales_agent = _SalesAgentResource(self)
        self.campaigns = _CampaignsResource(self)
        self.contacts = _ContactsResource(self)
        self.conversations = _ConversationsResource(self)
        self.settings = _SettingsResource(self)
        self.workspaces = _WorkspacesResource(self)
        self.ads = _AdsResource(self)
        self.campaign_templates = _CampaignTemplatesResource(self)
        self.deliverability = _DeliverabilityResource(self)
        self.notifications = _NotificationsResource(self)
        self.webhooks = _WebhooksResource(self)
