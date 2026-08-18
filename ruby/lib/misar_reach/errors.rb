module MisarReach
  # Base error raised for any non-2xx MisarReach API response.
  class ApiError < StandardError
    attr_reader :status, :code, :retry_after, :body

    def initialize(status, message, code: nil, retry_after: nil, body: nil)
      @status      = status
      @code        = code
      @retry_after = retry_after
      @body        = body
      super("misar-reach: API error #{status}#{code ? " (#{code})" : ""}: #{message}")
    end
  end

  # 401 / 403 — missing, invalid, or insufficiently-scoped `mrk_` key.
  class AuthError < ApiError
    def initialize(message = "Unauthorized", status: 401, **opts)
      super(status, message, code: opts[:code] || "unauthorized", **opts.reject { |k, _| k == :code })
    end
  end

  # 404 — resource not found.
  class NotFoundError < ApiError
    def initialize(message = "Not found", **opts)
      super(404, message, code: opts[:code] || "not_found", **opts.reject { |k, _| k == :code })
    end
  end

  # 429 — rate limited. `retry_after` carries the seconds to wait when provided.
  class RateLimitError < ApiError
    attr_reader :balance, :free_remaining

    def initialize(message = "Too many requests", retry_after: nil, balance: nil, free_remaining: nil, **opts)
      @balance        = balance
      @free_remaining = free_remaining
      super(429, message, code: opts[:code] || "rate_limit", retry_after: retry_after, body: opts[:body])
    end
  end

  # 429 with `upgrade: true` — the workspace plan must be upgraded to proceed.
  # A counted plan cap was hit.
  #
  # MisarReach answers 402 with +upgrade: true+ when a cap is reached and names
  # the offending counter. Retrying cannot help until the cap resets or the
  # plan changes.
  #
  # Distinct from the 503 +retry: true+ the server sends when it could not
  # *check* the quota: that one is retried, so "we do not know" is never
  # mistaken for "you are over your limit".
  class UpgradeRequiredError < ApiError
    APP_ORIGIN = "https://misarreach.com".freeze

    # @return [String, nil] the counter that was exhausted, e.g. "lead_searches"
    attr_reader :feature
    # @return [Integer, nil] the cap on the current plan
    attr_reader :limit
    # @return [Integer, nil] usage against that cap when the call was refused
    attr_reader :current
    # @return [String, nil] absolute URL to the billing page
    attr_reader :upgrade_url

    def initialize(message = "Upgrade required", **opts)
      body       = opts[:body] || {}
      @feature   = body["feature"]
      @limit     = body["limit"]
      @current   = body["current"]
      # The server sends an app-relative path; make it linkable.
      url = body["upgrade_url"]
      @upgrade_url =
        if url.nil? || url.start_with?("http://", "https://")
          url
        else
          APP_ORIGIN + (url.start_with?("/") ? url : "/#{url}")
        end
      super(opts[:status] || 402, message,
            code: opts[:code] || "upgrade_required",
            **opts.reject { |k, _| %i[code status].include?(k) })
    end
  end

  # Connectivity failure — no HTTP response received.
  class NetworkError < ApiError
    def initialize(message, cause = nil)
      super(0, message, code: "network_error")
      @cause = cause
    end
  end
end
