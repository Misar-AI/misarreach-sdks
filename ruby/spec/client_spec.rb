require "spec_helper"

RSpec.describe MisarReach::Client do
  let(:base_url) { "https://api.misar.io/reach/api" }
  let(:client)   { described_class.new(api_key: "mrk_test", max_retries: 1) }

  def stub(method, path, status:, body:, headers: {})
    stub_request(method, "#{base_url}#{path}")
      .to_return(status: status, body: body.to_json,
                 headers: { "Content-Type" => "application/json" }.merge(headers))
  end

  it "requires an api_key" do
    expect { described_class.new(api_key: "") }.to raise_error(ArgumentError)
  end

  it "leads.search POSTs to /lead-finder/search" do
    stub(:post, "/lead-finder/search", status: 201, body: { "jobId" => "job_1" })
    resp = client.leads.search(query: "SaaS founders")
    expect(resp["jobId"]).to eq("job_1")
  end

  it "leads.list GETs /lead-finder/leads with query" do
    stub_request(:get, "#{base_url}/lead-finder/leads?limit=10")
      .to_return(status: 200, body: { "leads" => [], "total" => 0 }.to_json,
                 headers: { "Content-Type" => "application/json" })
    resp = client.leads.list(limit: 10)
    expect(resp["total"]).to eq(0)
  end

  it "deals.create POSTs to /deals" do
    stub(:post, "/deals", status: 201, body: { "id" => "deal_1" })
    resp = client.deals.create(title: "Acme", value: 5000)
    expect(resp["id"]).to eq("deal_1")
  end

  it "pipeline.get GETs /pipeline" do
    stub(:get, "/pipeline", status: 200, body: { "stages" => [] })
    expect(client.pipeline.get["stages"]).to eq([])
  end

  it "channels.status GETs /channels/status" do
    stub(:get, "/channels/status", status: 200, body: { "sms" => { "connected" => false } })
    expect(client.channels.status["sms"]["connected"]).to be false
  end

  it "channels.connect_whatsapp POSTs to /channels/whatsapp/connect" do
    stub(:post, "/channels/whatsapp/connect", status: 200, body: { "ok" => true })
    expect(client.channels.connect_whatsapp(token: "x")["ok"]).to be true
  end

  it "autopilot.start POSTs to /autopilot/start" do
    stub(:post, "/autopilot/start", status: 200, body: { "runId" => "run_1" })
    expect(client.autopilot.start(campaignId: "c1")["runId"]).to eq("run_1")
  end

  it "sales_agent.config GETs /sales-agent/config" do
    stub(:get, "/sales-agent/config", status: 200, body: { "enabled" => true })
    expect(client.sales_agent.config["enabled"]).to be true
  end

  it "contacts.stats GETs /contacts/stats" do
    stub(:get, "/contacts/stats", status: 200, body: { "total" => 42 })
    expect(client.contacts.stats["total"]).to eq(42)
  end

  it "settings.set_sender_address PUTs /settings/sender-address" do
    stub(:put, "/settings/sender-address", status: 200, body: { "ok" => true })
    expect(client.settings.set_sender_address(email: "a@b.com")["ok"]).to be true
  end

  it "raises AuthError on 401" do
    stub(:post, "/lead-finder/search", status: 401, body: { "error" => "Unauthorized" })
    expect { client.leads.search({}) }
      .to raise_error(MisarReach::AuthError) { |e| expect(e.status).to eq(401) }
  end

  it "raises NotFoundError on 404" do
    stub(:get, "/campaigns/nope", status: 404, body: { "error" => "not found" })
    expect { client.campaigns.get("nope") }.to raise_error(MisarReach::NotFoundError)
  end

  it "raises RateLimitError on 429 with retryAfter" do
    stub(:post, "/lead-finder/search", status: 429, body: { "error" => "slow down", "retryAfter" => 12 })
    expect { client.leads.search({}) }
      .to raise_error(MisarReach::RateLimitError) { |e| expect(e.retry_after).to eq(12) }
  end

  it "raises UpgradeRequiredError on 429 upgrade" do
    stub(:post, "/lead-finder/enrich", status: 429, body: { "error" => "upgrade", "upgrade" => true })
    expect { client.leads.enrich({}) }.to raise_error(MisarReach::UpgradeRequiredError)
  end

  it "retries on 503 then succeeds" do
    c = described_class.new(api_key: "mrk_test", max_retries: 2)
    stub_request(:get, "#{base_url}/pipeline")
      .to_return(
        { status: 503, body: { "error" => "down" }.to_json, headers: { "Content-Type" => "application/json" } },
        { status: 200, body: { "stages" => [] }.to_json, headers: { "Content-Type" => "application/json" } }
      )
    allow(c).to receive(:sleep)
    expect(c.pipeline.get["stages"]).to eq([])
  end

  it "raises NetworkError on connection failure" do
    stub_request(:get, "#{base_url}/pipeline").to_raise(Errno::ECONNREFUSED)
    expect { client.pipeline.get }.to raise_error(MisarReach::NetworkError)
  end

  it "streams SSE events from a lead-finder job" do
    sse = "event: progress\ndata: {\"pct\":50}\n\nevent: done\ndata: {\"leads\":3}\n\n"
    stub_request(:get, "#{base_url}/lead-finder/jobs/job_1/stream")
      .to_return(status: 200, body: sse, headers: { "Content-Type" => "text/event-stream" })
    events = []
    client.leads.stream_job("job_1") { |e| events << e }
    expect(events.first[:event]).to eq("progress")
    expect(events.first[:data]["pct"]).to eq(50)
    expect(events.last[:data]["leads"]).to eq(3)
  end
end
