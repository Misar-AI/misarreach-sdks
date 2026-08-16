import httpx
import pytest
import respx

from misar_reach import (
    MisarReachClient,
    ReachAPIError,
    ReachAuthError,
    ReachRateLimitError,
)

BASE = "https://api.misar.io/reach/api"


def make_client(**kwargs) -> MisarReachClient:
    return MisarReachClient(api_key="mrk_test", **kwargs)


@respx.mock
async def test_leads_search():
    respx.post(f"{BASE}/lead-finder/search").mock(
        return_value=httpx.Response(200, json={"jobId": "job_1", "status": "queued"})
    )
    client = make_client()
    resp = await client.leads.asearch({"query": "SaaS founders", "useAI": True})
    assert resp["jobId"] == "job_1"


@respx.mock
async def test_leads_list_sync():
    respx.get(f"{BASE}/lead-finder/leads").mock(
        return_value=httpx.Response(200, json={"leads": [], "total": 0})
    )
    client = make_client()
    resp = client.leads.list(page=1, limit=50)
    assert resp["total"] == 0


@respx.mock
async def test_deals_create():
    respx.post(f"{BASE}/deals").mock(
        return_value=httpx.Response(200, json={"id": "deal_1", "value": 5000})
    )
    client = make_client()
    resp = await client.deals.acreate({"leadEmail": "a@b.com", "value": 5000})
    assert resp["id"] == "deal_1"


@respx.mock
async def test_pipeline_move():
    respx.post(f"{BASE}/pipeline").mock(
        return_value=httpx.Response(200, json={"ok": True})
    )
    client = make_client()
    resp = await client.pipeline.amove({"dealId": "deal_1", "stage": "interested"})
    assert resp["ok"] is True


@respx.mock
async def test_channels_status():
    respx.get(f"{BASE}/channels/status").mock(
        return_value=httpx.Response(200, json={"whatsapp": {"enabled": True}})
    )
    client = make_client()
    resp = await client.channels.astatus()
    assert resp["whatsapp"]["enabled"] is True


@respx.mock
async def test_channels_connect_validates():
    client = make_client()
    with pytest.raises(ValueError):
        await client.channels.aconnect("myspace", {})


@respx.mock
async def test_autopilot_start():
    respx.post(f"{BASE}/autopilot/start").mock(
        return_value=httpx.Response(200, json={"id": "run_1", "status": "running"})
    )
    client = make_client()
    resp = await client.autopilot.astart({"goal": "book meetings"})
    assert resp["id"] == "run_1"


@respx.mock
async def test_sales_agent_config():
    respx.get(f"{BASE}/sales-agent/config").mock(
        return_value=httpx.Response(200, json={"enabled": True, "confidence": 0.7})
    )
    client = make_client()
    resp = await client.sales_agent.aconfig()
    assert resp["enabled"] is True


@respx.mock
async def test_contacts_bulk():
    respx.post(f"{BASE}/contacts/bulk").mock(
        return_value=httpx.Response(200, json={"deleted": 2})
    )
    client = make_client()
    resp = await client.contacts.abulk({"action": "delete", "ids": ["a", "b"]})
    assert resp["deleted"] == 2


@respx.mock
async def test_conversations_list_query():
    route = respx.get(f"{BASE}/conversations").mock(
        return_value=httpx.Response(200, json={"conversations": []})
    )
    client = make_client()
    await client.conversations.alist(status="open", channel="whatsapp", limit=10)
    assert route.called
    assert "status=open" in str(route.calls.last.request.url)


@respx.mock
async def test_error_401_auth():
    respx.get(f"{BASE}/lead-finder/leads").mock(
        return_value=httpx.Response(401, json={"error": "Invalid key"})
    )
    client = make_client()
    with pytest.raises(ReachAuthError) as exc:
        await client.leads.alist()
    assert exc.value.status == 401


@respx.mock
async def test_error_429_rate_limit():
    respx.post(f"{BASE}/lead-finder/search").mock(
        return_value=httpx.Response(429, json={"error": "slow down", "success": False, "retryAfter": 5})
    )
    client = make_client(max_retries=1)
    with pytest.raises(ReachRateLimitError) as exc:
        await client.leads.asearch({"query": "x"})
    assert exc.value.retry_after == 5


@respx.mock
async def test_error_500_generic():
    respx.get(f"{BASE}/deals").mock(
        return_value=httpx.Response(500, json={"error": "boom"})
    )
    client = make_client(max_retries=1)
    with pytest.raises(ReachAPIError) as exc:
        await client.deals.alist()
    assert exc.value.status == 500


def test_sse_parse_block():
    from misar_reach.client import _ReachCore

    evt = _ReachCore._parse_sse_block('event: progress\ndata: {"message": "found", "total_found": 3}')
    assert evt is not None
    assert evt.event == "progress"
    assert evt.data["total_found"] == 3


@respx.mock
def test_stream_job_sync():
    body = 'event: progress\ndata: {"total_found": 1}\n\nevent: complete\ndata: {"total_found": 2}\n\n'
    respx.get(f"{BASE}/lead-finder/jobs/job_1/stream").mock(
        return_value=httpx.Response(
            200, headers={"content-type": "text/event-stream"}, text=body
        )
    )
    client = make_client()
    events = list(client.leads.stream_job("job_1"))
    assert [e.event for e in events] == ["progress", "complete"]
    assert events[-1].data["total_found"] == 2


@respx.mock
def test_stream_job_finished_snapshot():
    respx.get(f"{BASE}/lead-finder/jobs/job_2/stream").mock(
        return_value=httpx.Response(200, json={"status": "completed", "total_found": 9})
    )
    client = make_client()
    events = list(client.leads.stream_job("job_2"))
    assert len(events) == 1
    assert events[0].event == "complete"
    assert events[0].data["total_found"] == 9
