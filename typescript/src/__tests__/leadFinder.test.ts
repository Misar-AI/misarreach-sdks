import assert from "node:assert/strict";
import { describe, it, afterEach } from "node:test";
import { LeadFinderResource, type LeadFinderStreamEvent } from "../resources/leadFinder.js";
import { UpgradeRequiredError, AuthError, MisarReachError } from "../errors.js";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Replies with an SSE body delivered in the given pieces. */
function stubStream(pieces: string[], init: { status?: number } = {}) {
  globalThis.fetch = (async () =>
    new Response(
      new ReadableStream<Uint8Array>({
        start(controller) {
          const encoder = new TextEncoder();
          for (const piece of pieces) controller.enqueue(encoder.encode(piece));
          controller.close();
        },
      }),
      {
        status: init.status ?? 200,
        headers: { "content-type": "text/event-stream" },
      },
    )) as typeof globalThis.fetch;
}

/** Replies with a JSON body, as the route does for an already-finished job. */
function stubJson(body: unknown, status = 200) {
  globalThis.fetch = (async () =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    })) as typeof globalThis.fetch;
}

function resource() {
  const request = (async () => {
    throw new Error("the stream must not go through the JSON helper");
  }) as <T>(m: string, p: string, b?: unknown) => Promise<T>;
  return new LeadFinderResource(request, "https://api.misar.io/reach/api", "test-key");
}

async function collect(jobId = "job_1"): Promise<LeadFinderStreamEvent[]> {
  const seen: LeadFinderStreamEvent[] = [];
  for await (const event of resource().stream(jobId)) seen.push(event);
  return seen;
}

describe("leadFinder.stream", () => {
  it("yields each named frame", async () => {
    // The frame boundary is deliberately split across two chunks.
    stubStream([
      'event: progress\ndata: {"message":"searching"}\n',
      '\nevent: found\ndata: {"total":12}\n\n',
      ": keepalive\n\n",
      'event: complete\ndata: {"total_found":12}\n\n',
    ]);

    const seen = await collect();

    assert.deepEqual(
      seen.map((e) => e.event),
      ["progress", "found", "complete"],
    );
    assert.deepEqual(seen[1].data, { total: 12 });
  });

  it("skips keepalive comments without yielding an event", async () => {
    stubStream([": keepalive\n\n", ": keepalive\n\n", 'event: complete\ndata: {}\n\n']);

    const seen = await collect();

    assert.equal(seen.length, 1);
    assert.equal(seen[0].event, "complete");
  });

  it("tolerates CRLF frame separators", async () => {
    stubStream(['event: progress\r\ndata: {"message":"x"}\r\n\r\n']);

    const seen = await collect();

    assert.equal(seen.length, 1);
    assert.deepEqual(seen[0].data, { message: "x" });
  });

  it("synthesises a terminal frame when a finished job answers with JSON", async () => {
    // The route returns a snapshot rather than a stream once a job is done.
    // Before this was handled the iterator completed with zero events and the
    // caller could not tell a finished job from a silent one.
    stubJson({
      status: "done",
      progress: null,
      total_found: 42,
      error: null,
      completed_at: "2026-08-17T00:00:00Z",
    });

    const seen = await collect();

    assert.equal(seen.length, 1);
    assert.equal(seen[0].event, "complete");
    assert.equal((seen[0].data as { total_found: number }).total_found, 42);
  });

  it("reports a failed job as an error frame, not a complete one", async () => {
    stubJson({ status: "failed", error: "no sources reachable", total_found: 0 });

    const seen = await collect();

    assert.equal(seen[0].event, "error");
    assert.equal((seen[0].data as { error: string }).error, "no sources reachable");
  });

  it("raises the typed plan error on a 402 refusal", async () => {
    stubJson(
      {
        error: "monthly lead searches used up",
        upgrade: true,
        feature: "lead_searches",
        limit: 50,
        current: 50,
        upgrade_url: "/settings?tab=billing",
      },
      402,
    );

    await assert.rejects(collect(), (error: unknown) => {
      assert.ok(error instanceof UpgradeRequiredError, `got ${error}`);
      assert.equal(error.status, 402);
      assert.equal(error.feature, "lead_searches");
      assert.equal(error.limit, 50);
      assert.equal(error.current, 50);
      // The server sends an app-relative path; the SDK resolves it.
      assert.equal(error.upgradeUrl, "https://misarreach.com/settings?tab=billing");
      return true;
    });
  });

  it("raises AuthError on a 401", async () => {
    stubJson({ error: "invalid api key" }, 401);

    await assert.rejects(collect(), (error: unknown) => {
      assert.ok(error instanceof AuthError, `got ${error}`);
      return true;
    });
  });

  it("does not mistake a 503 quota-check failure for a refusal", async () => {
    // The server answers 503 with `retry: true` when it could not check the
    // quota. Treating that as a plan refusal would tell the caller to upgrade
    // over what is actually a transient fault.
    stubJson({ error: "could not verify quota", retry: true }, 503);

    await assert.rejects(collect(), (error: unknown) => {
      assert.ok(error instanceof MisarReachError, `got ${error}`);
      assert.ok(!(error instanceof UpgradeRequiredError));
      assert.equal((error as MisarReachError).status, 503);
      return true;
    });
  });

  it("yields a trailing frame the server never closed with a blank line", async () => {
    stubStream(['event: complete\ndata: {"total_found":1}']);

    const seen = await collect();

    assert.equal(seen.length, 1);
    assert.equal(seen[0].event, "complete");
  });

  it("percent-encodes the job id", async () => {
    let seenUrl = "";
    globalThis.fetch = (async (url: string | URL) => {
      seenUrl = String(url);
      return new Response("", { status: 200, headers: { "content-type": "text/event-stream" } });
    }) as typeof globalThis.fetch;

    await collect("job/with slash");

    assert.ok(seenUrl.endsWith("/lead-finder/jobs/job%2Fwith%20slash/stream"), seenUrl);
  });
});
