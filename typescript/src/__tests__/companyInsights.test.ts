import assert from "node:assert/strict";
import { describe, it, afterEach } from "node:test";
import { MisarReachClient } from "../client.js";
import { NotFoundError } from "../errors.js";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Records every request and answers with `body` / `status`. */
function stub(body: unknown, status = 200) {
  const seen: Array<{ url: string; method: string; body: unknown; auth: string | null }> = [];
  globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
    seen.push({
      url: String(input),
      method: init.method ?? "GET",
      body: init.body ? JSON.parse(String(init.body)) : undefined,
      auth: new Headers(init.headers).get("authorization"),
    });
    return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  }) as typeof globalThis.fetch;
  return seen;
}

const reach = () => new MisarReachClient("mrk_test");

describe("leadFinder.revealCompanySite", () => {
  it("GETs the company site route with the key", async () => {
    const seen = stub({ domain: "acme.com", emails: ["hello@acme.com"], has_contact: true, charged: true });
    const r = await reach().leadFinder.revealCompanySite("acme.com");
    assert.equal(seen[0]!.url, "https://api.misar.io/reach/api/lead-finder/companies/acme.com/site");
    assert.equal(seen[0]!.method, "GET");
    assert.equal(seen[0]!.auth, "Bearer mrk_test");
    assert.deepEqual(r.emails, ["hello@acme.com"]);
  });
});

describe("leadFinder.companyBrief", () => {
  it("POSTs the person to the brief route", async () => {
    const seen = stub({ domain: "acme.com", brief: null, reason: "not_enough_text", message: null });
    const r = await reach().leadFinder.companyBrief("acme.com", { name: "Jane Doe", role: "VP Sales" });
    assert.equal(seen[0]!.url, "https://api.misar.io/reach/api/lead-finder/companies/acme.com/brief");
    assert.equal(seen[0]!.method, "POST");
    assert.deepEqual(seen[0]!.body, { name: "Jane Doe", role: "VP Sales" });
    assert.equal(r.reason, "not_enough_text");
  });

  it("sends an empty body when no person is named", async () => {
    const seen = stub({ domain: "acme.com", brief: null, message: null });
    await reach().leadFinder.companyBrief("acme.com");
    assert.deepEqual(seen[0]!.body, {});
  });
});

describe("leadFinder.emailFormat", () => {
  it("GETs the public format route", async () => {
    const seen = stub({ domain: "acme.com", verifiedAddresses: 9, top: { pattern: "first.last" }, patterns: [], confidence: "high" });
    const f = await reach().leadFinder.emailFormat("acme.com");
    assert.equal(seen[0]!.url, "https://api.misar.io/reach/api/public/email-formats/acme.com");
    assert.equal(f.top.pattern, "first.last");
  });

  it("raises NotFoundError when no format is published yet", async () => {
    stub({ error: "Not enough verified addresses", domain: "tiny.io" }, 404);
    await assert.rejects(reach().leadFinder.emailFormat("tiny.io"), NotFoundError);
  });
});
