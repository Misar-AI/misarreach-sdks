require "net/http"
require "uri"
require "json"

module MisarReach
  BASE_URL     = "https://api.misar.io/reach/api".freeze
  RETRYABLE    = [429, 500, 502, 503, 504].freeze
  RETRY_BASE_S = 0.3

  # ── Resource base ────────────────────────────────────────────────────────────

  class Resource
    def initialize(client)
      @client = client
    end

    private

    def qs(params)
      return "" if params.nil? || params.empty?
      "?#{URI.encode_www_form(params)}"
    end
  end

  # ── Resource: Lead Finder (leads) ────────────────────────────────────────────
  #
  # 23-source lead discovery, enrichment, verification, scoring, lists,
  # saved searches, scoring rules, recommendations, and the SSE job stream.
  class LeadsResource < Resource
    def account
      @client.request(:get, "/lead-finder/account")
    end

    def config
      @client.request(:get, "/lead-finder/config")
    end

    # Synchronous lead lookup.
    def list(params = {})
      @client.request(:get, "/lead-finder/leads#{qs(params)}")
    end

    # Start an async lead search — returns a jobId; poll `job(job_id)` or
    # consume `stream_job(job_id)` for live progress.
    def search(data)
      @client.request(:post, "/lead-finder/search", data)
    end

    def discover(data)
      @client.request(:post, "/lead-finder/discover", data)
    end

    def enrich(data)
      @client.request(:post, "/lead-finder/enrich", data)
    end

    def verify(data)
      @client.request(:post, "/lead-finder/verify", data)
    end

    def score(data)
      @client.request(:post, "/lead-finder/score", data)
    end

    def export(params = {})
      @client.request(:get, "/lead-finder/export#{qs(params)}")
    end

    def search_history(params = {})
      @client.request(:get, "/lead-finder/search-history#{qs(params)}")
    end

    def recommendations(params = {})
      @client.request(:get, "/lead-finder/recommendations#{qs(params)}")
    end

    def preview_message(data)
      @client.request(:post, "/lead-finder/preview-message", data)
    end

    def send_to_campaign(data)
      @client.request(:post, "/lead-finder/send-to-campaign", data)
    end

    def add_to_segment(data)
      @client.request(:post, "/lead-finder/add-to-segment", data)
    end

    def company(domain)
      @client.request(:get, "/lead-finder/companies/#{URI.encode_www_form_component(domain)}")
    end

    def company_people(domain, params = {})
      @client.request(:get, "/lead-finder/companies/#{URI.encode_www_form_component(domain)}/people#{qs(params)}")
    end

    # ── Lists ──
    def lists(params = {})
      @client.request(:get, "/lead-finder/lists#{qs(params)}")
    end

    def create_list(data)
      @client.request(:post, "/lead-finder/lists", data)
    end

    def sync_list(list_id, data = {})
      @client.request(:post, "/lead-finder/lists/#{list_id}/sync", data)
    end

    # ── Saved searches ──
    def saved_searches(params = {})
      @client.request(:get, "/lead-finder/saved-searches#{qs(params)}")
    end

    def create_saved_search(data)
      @client.request(:post, "/lead-finder/saved-searches", data)
    end

    def delete_saved_search(id)
      @client.request(:delete, "/lead-finder/saved-searches/#{id}")
    end

    # ── Scoring rules ──
    def scoring_rules(params = {})
      @client.request(:get, "/lead-finder/scoring-rules#{qs(params)}")
    end

    def create_scoring_rule(data)
      @client.request(:post, "/lead-finder/scoring-rules", data)
    end

    def update_scoring_rule(id, data)
      @client.request(:patch, "/lead-finder/scoring-rules/#{id}", data)
    end

    def delete_scoring_rule(id)
      @client.request(:delete, "/lead-finder/scoring-rules/#{id}")
    end

    # ── Jobs ──
    def job(job_id)
      @client.request(:get, "/lead-finder/jobs/#{job_id}")
    end

    def job_feedback(job_id, data)
      @client.request(:post, "/lead-finder/jobs/#{job_id}/feedback", data)
    end

    # Server-Sent Events stream for a running lead-finder job.
    #
    # Yields each parsed event as a Hash: { event:, data: } where `data` is the
    # JSON-decoded `data:` payload (or the raw string if not JSON). Blocks until
    # the stream closes. Requires a block.
    #
    #   client.leads.stream_job(job_id) do |evt|
    #     puts evt[:event], evt[:data]
    #   end
    def stream_job(job_id, &block)
      raise ArgumentError, "stream_job requires a block" unless block_given?
      @client.stream(:get, "/lead-finder/jobs/#{job_id}/stream", &block)
    end
  end

  # ── Resource: Deals ──────────────────────────────────────────────────────────

  class DealsResource < Resource
    def list(params = {})
      @client.request(:get, "/deals#{qs(params)}")
    end

    def create(data)
      @client.request(:post, "/deals", data)
    end

    def update(id, data)
      @client.request(:patch, "/deals/#{id}", data)
    end

    def delete(id)
      @client.request(:delete, "/deals/#{id}")
    end

    def activity(id, params = {})
      @client.request(:get, "/deals/#{id}/activity#{qs(params)}")
    end

    # Apply one operation to many deals at once —
    # `{ ids: [...], op: "tag"|"untag"|"stage"|"delete", ... }`. Tag writes are
    # applied atomically server-side, so concurrent callers cannot lose a tag.
    def bulk(data)
      @client.request(:post, "/deals/bulk", data)
    end

    def suggestions(id, params = {})
      @client.request(:get, "/deals/#{id}/suggestions#{qs(params)}")
    end
  end

  # ── Resource: Pipeline ───────────────────────────────────────────────────────

  class PipelineResource < Resource
    def get(params = {})
      @client.request(:get, "/pipeline#{qs(params)}")
    end

    # Move a deal / reorder the pipeline board.
    def update(data)
      @client.request(:post, "/pipeline", data)
    end
  end

  # ── Resource: Channels ───────────────────────────────────────────────────────

  class ChannelsResource < Resource
    def status
      @client.request(:get, "/channels/status")
    end

    def update_status(data)
      @client.request(:patch, "/channels/status", data)
    end

    def opt_in_links(params = {})
      @client.request(:get, "/channels/opt-in-links#{qs(params)}")
    end

    def connect_sms(data)
      @client.request(:post, "/channels/sms/connect", data)
    end

    def connect_whatsapp(data)
      @client.request(:post, "/channels/whatsapp/connect", data)
    end

    def connect_telegram(data)
      @client.request(:post, "/channels/telegram/connect", data)
    end

    def connect_twitter(data)
      @client.request(:post, "/channels/twitter/connect", data)
    end

    def connect_instagram(data)
      @client.request(:post, "/channels/instagram/connect", data)
    end

    def connect_facebook(data)
      @client.request(:post, "/channels/facebook/connect", data)
    end

    def connect_discord(data)
      @client.request(:post, "/channels/discord/connect", data)
    end

    def subscribe_push(data)
      @client.request(:post, "/channels/push/subscribe", data)
    end

    def unsubscribe_push
      @client.request(:delete, "/channels/push/subscribe")
    end
  end

  # ── Resource: Autopilot ──────────────────────────────────────────────────────

  class AutopilotResource < Resource
    def start(data)
      @client.request(:post, "/autopilot/start", data)
    end

    def runs(params = {})
      @client.request(:get, "/autopilot/runs#{qs(params)}")
    end

    def get(id)
      @client.request(:get, "/autopilot/#{id}")
    end

    def status(id)
      @client.request(:get, "/autopilot/#{id}/status")
    end

    def set_status(id, data)
      @client.request(:post, "/autopilot/#{id}/status", data)
    end
  end

  # ── Resource: Sales Agent ────────────────────────────────────────────────────

  class SalesAgentResource < Resource
    def config
      @client.request(:get, "/sales-agent/config")
    end

    def update_config(data)
      @client.request(:patch, "/sales-agent/config", data)
    end

    def actions(params = {})
      @client.request(:get, "/sales-agent/actions#{qs(params)}")
    end

    def conversations(params = {})
      @client.request(:get, "/sales-agent/conversations#{qs(params)}")
    end

    def process(data)
      @client.request(:post, "/sales-agent/process", data)
    end
  end

  # ── Resource: Campaigns ──────────────────────────────────────────────────────

  class CampaignsResource < Resource
    def list(params = {})
      @client.request(:get, "/campaigns#{qs(params)}")
    end

    def create(data)
      @client.request(:post, "/campaigns", data)
    end

    def get(id)
      @client.request(:get, "/campaigns/#{id}")
    end

    def update(id, data)
      @client.request(:patch, "/campaigns/#{id}", data)
    end

    def delete(id)
      @client.request(:delete, "/campaigns/#{id}")
    end

    def enqueue(id, data = {})
      @client.request(:post, "/campaigns/#{id}/enqueue", data)
    end
  end

  # ── Resource: Contacts ───────────────────────────────────────────────────────

  class ContactsResource < Resource
    def list(params = {})
      @client.request(:get, "/contacts#{qs(params)}")
    end

    def create(data)
      @client.request(:post, "/contacts", data)
    end

    def get(id)
      @client.request(:get, "/contacts/#{id}")
    end

    def update(id, data)
      @client.request(:patch, "/contacts/#{id}", data)
    end

    def delete(id)
      @client.request(:delete, "/contacts/#{id}")
    end

    def bulk(data)
      @client.request(:post, "/contacts/bulk", data)
    end

    def import_contacts(data)
      @client.request(:post, "/contacts/import", data)
    end

    def segments(params = {})
      @client.request(:get, "/contacts/segments#{qs(params)}")
    end

    def stats(params = {})
      @client.request(:get, "/contacts/stats#{qs(params)}")
    end
  end

  # ── Resource: Conversations ──────────────────────────────────────────────────

  class ConversationsResource < Resource
    def list(params = {})
      @client.request(:get, "/conversations#{qs(params)}")
    end

    def get(email)
      @client.request(:get, "/conversations/#{URI.encode_www_form_component(email)}")
    end

    def reply(email, data)
      @client.request(:post, "/conversations/#{URI.encode_www_form_component(email)}/reply", data)
    end
  end

  # ── Resource: Campaign templates ─────────────────────────────────────────────

  class CampaignTemplatesResource < Resource
    def list(params = {})
      @client.request(:get, "/campaign-templates#{qs(params)}")
    end

    def create(data)
      @client.request(:post, "/campaign-templates", data)
    end
  end

  # ── Resource: Deliverability ─────────────────────────────────────────────────

  class DeliverabilityResource < Resource
    # Sender health. `bounceRate` and `complaintRate` are nil when there is not
    # enough volume to judge — which is not the same as zero.
    def get(params = {})
      @client.request(:get, "/deliverability#{qs(params)}")
    end
  end

  # ── Resource: Notifications ──────────────────────────────────────────────────

  class NotificationsResource < Resource
    def list(params = {})
      @client.request(:get, "/notifications#{qs(params)}")
    end

    # Mark notifications read. Pass `{ ids: [...] }` or `{ all: true }`.
    def mark_read(data)
      @client.request(:patch, "/notifications", data)
    end
  end

  # ── Resource: Webhooks ───────────────────────────────────────────────────────

  class WebhooksResource < Resource
    def list
      @client.request(:get, "/webhooks/endpoints")
    end

    # Register an endpoint. The response carries the signing secret exactly
    # once — store it then; it is not retrievable afterwards.
    def create(data)
      @client.request(:post, "/webhooks/endpoints", data)
    end
  end

  # ── Resource: Workspaces ─────────────────────────────────────────────────────

  class WorkspacesResource < Resource
    def list(params = {})
      @client.request(:get, "/workspaces#{qs(params)}")
    end

    def create(data)
      @client.request(:post, "/workspaces", data)
    end

    def members(id)
      @client.request(:get, "/workspaces/#{id}/members")
    end

    def add_member(id, data)
      @client.request(:post, "/workspaces/#{id}/members", data)
    end

    def remove_member(id)
      @client.request(:delete, "/workspaces/#{id}/members")
    end
  end

  # ── Resource: Settings ───────────────────────────────────────────────────────

  # The subscription behind the API key.
  #
  # Read this before an expensive run rather than discovering the ceiling through
  # an UpgradeRequiredError halfway through: a 402 says a call *was* refused,
  # whereas +usage+ says what is left before anything is spent.
  class PlanResource < Resource
    # GET /plan — plan, caps, per-feature usage and the upgrade offer.
    #
    # A null limit means unlimited, and +remaining+ is nil with it rather than 0
    # — 0 would read as exhausted.
    def get
      @client.request(:get, "/plan")
    end
  end

  class SettingsResource < Resource
    def sender_address
      @client.request(:get, "/settings/sender-address")
    end

    def set_sender_address(data)
      @client.request(:put, "/settings/sender-address", data)
    end
  end

  # ── Resource: Ads ────────────────────────────────────────────────────────────

  class AdsResource < Resource
    def linkedin_company_audience(data)
      @client.request(:post, "/ads/linkedin/company-audience", data)
    end
  end

  # ── Main Client ──────────────────────────────────────────────────────────────

  class Client
    attr_reader :leads, :deals, :pipeline, :channels, :autopilot, :sales_agent,
                :campaigns, :contacts, :conversations, :workspaces, :settings, :ads,
                :campaign_templates, :deliverability, :notifications, :webhooks,
                :plan

    # @param api_key [String] a reach developer key (`mrk_...`)
    def initialize(api_key:, base_url: BASE_URL, timeout: 30, max_retries: 3)
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key     = api_key
      @base_url    = base_url.chomp("/")
      @timeout     = timeout
      @max_retries = max_retries

      @leads         = LeadsResource.new(self)
      @deals         = DealsResource.new(self)
      @pipeline      = PipelineResource.new(self)
      @channels      = ChannelsResource.new(self)
      @autopilot     = AutopilotResource.new(self)
      @sales_agent   = SalesAgentResource.new(self)
      @campaigns     = CampaignsResource.new(self)
      @contacts      = ContactsResource.new(self)
      @conversations = ConversationsResource.new(self)
      @workspaces    = WorkspacesResource.new(self)
      @settings      = SettingsResource.new(self)
      @plan          = PlanResource.new(self)
      @ads           = AdsResource.new(self)
      @campaign_templates = CampaignTemplatesResource.new(self)
      @deliverability     = DeliverabilityResource.new(self)
      @notifications      = NotificationsResource.new(self)
      @webhooks           = WebhooksResource.new(self)
    end

    # @param method [Symbol] :get, :post, :patch, :put, :delete
    # @param path   [String] e.g. "/deals"
    # @param data   [Hash]   request body (post/put/patch only)
    # @return [Hash]
    # @raise [ApiError, NetworkError]
    def request(method, path, data = {})
      url       = URI.parse(@base_url + "/" + path.delete_prefix("/"))
      has_body  = !data.nil? && !data.empty? && %i[post put patch].include?(method)
      json_body = has_body ? JSON.generate(data) : nil

      last_status = 0

      @max_retries.times do |attempt|
        begin
          http = build_http(url)
          req  = build_request(method, url, json_body)
          resp = http.request(req)
          last_status = resp.code.to_i

          if RETRYABLE.include?(last_status) && attempt < @max_retries - 1
            sleep(backoff_seconds(resp, attempt))
            next
          end

          return parse_response(resp, last_status)
        rescue Net::OpenTimeout, Net::ReadTimeout,
               Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError => e
          if attempt < @max_retries - 1
            sleep(RETRY_BASE_S * (2**attempt))
            next
          end
          raise NetworkError.new(e.message, e)
        end
      end

      raise ApiError.new(last_status, "Max retries exceeded")
    end

    # Streaming request for Server-Sent Events. Yields { event:, data: } hashes.
    def stream(method, path, &block)
      url = URI.parse(@base_url + "/" + path.delete_prefix("/"))
      http = build_http(url)
      req  = build_request(method, url, nil)
      req["Accept"] = "text/event-stream"

      http.request(req) do |resp|
        status = resp.code.to_i
        raise_for_status(status, resp.body) if status >= 400

        # The route does not always stream. A job that has already finished is
        # answered with a JSON snapshot, because there is nothing left to
        # stream. Parsing that as SSE finds no frames and returns silently, so
        # the caller would see nothing rather than the outcome. Synthesise the
        # terminal event the SSE path would have sent.
        unless resp["content-type"].to_s.include?("text/event-stream")
          body = +""
          resp.read_body { |chunk| body << chunk }
          snapshot = begin
            JSON.parse(body)
          rescue JSON::ParserError
            body
          end
          name = snapshot.is_a?(Hash) && snapshot["status"] == "failed" ? "error" : "complete"
          block.call({ event: name, data: snapshot })
          return nil
        end

        buffer = +""
        resp.read_body do |chunk|
          buffer << chunk
          while (idx = buffer.index("\n\n"))
            raw   = buffer.slice!(0..idx + 1)
            event = parse_sse_block(raw)
            block.call(event) if event
          end
        end
      end
      nil
    end

    private

    def build_http(url)
      http              = Net::HTTP.new(url.host, url.port)
      http.use_ssl      = url.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = @timeout
      http
    end

    def build_request(method, url, json_body)
      klass = case method
              when :get    then Net::HTTP::Get
              when :post   then Net::HTTP::Post
              when :patch  then Net::HTTP::Patch
              when :put    then Net::HTTP::Put
              when :delete then Net::HTTP::Delete
              else raise ArgumentError, "Unsupported HTTP method: #{method}"
              end

      req = klass.new(url.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Content-Type"]  = "application/json"
      req["Accept"]        = "application/json"
      req["User-Agent"]    = "misar-reach-ruby/1.0.0"
      req.body = json_body if json_body
      req
    end

    def backoff_seconds(resp, attempt)
      ra = resp["Retry-After"]
      return ra.to_f if ra && ra.to_f > 0
      RETRY_BASE_S * (2**attempt)
    end

    def parse_response(resp, status)
      return {} if status == 204 || resp.body.nil? || resp.body.empty?

      decoded = begin
        JSON.parse(resp.body)
      rescue JSON::ParserError
        nil
      end

      raise_for_status(status, resp.body, decoded) if status >= 400

      decoded.is_a?(Hash) ? decoded : { "data" => decoded }
    end

    def raise_for_status(status, raw_body, decoded = nil)
      decoded ||= begin
        JSON.parse(raw_body)
      rescue StandardError
        nil
      end
      h = decoded.is_a?(Hash) ? decoded : {}
      err = h["error"]
      msg = err.is_a?(String) ? err : (h["message"] || (err && err.to_s) || raw_body.to_s)
      code = h["code"]
      retry_after = h["retryAfter"]

      case status
      when 401, 403
        raise AuthError.new(msg, status: status, code: code, body: h)
      when 402
        # A counted cap answers 402 with `upgrade: true` (reach-gate.rb contract).
        # This branch did not exist, so every real refusal fell through to the
        # generic ApiError.
        raise UpgradeRequiredError.new(msg, code: code, body: h)

      when 404
        raise NotFoundError.new(msg, code: code, body: h)
      when 429
        # 429 with `upgrade` is the legacy shape; the server now answers 402.
        if h["upgrade"]
          raise UpgradeRequiredError.new(msg, code: code, body: h)
        end
        raise RateLimitError.new(msg, retry_after: retry_after,
                                      balance: h["balance"],
                                      free_remaining: h["freeRemaining"],
                                      code: code, body: h)
      else
        raise ApiError.new(status, msg, code: code, retry_after: retry_after, body: h)
      end
    end

    def parse_sse_block(raw)
      event_name = nil
      data_lines = []
      raw.each_line do |line|
        line = line.chomp
        next if line.empty? || line.start_with?(":")
        if line.start_with?("event:")
          event_name = line.sub(/^event:\s?/, "")
        elsif line.start_with?("data:")
          data_lines << line.sub(/^data:\s?/, "")
        end
      end
      return nil if data_lines.empty? && event_name.nil?

      payload = data_lines.join("\n")
      parsed = begin
        payload.empty? ? nil : JSON.parse(payload)
      rescue JSON::ParserError
        payload
      end
      { event: event_name, data: parsed }
    end
  end
end
