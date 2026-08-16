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
  class UpgradeRequiredError < ApiError
    def initialize(message = "Upgrade required", **opts)
      super(429, message, code: opts[:code] || "upgrade_required", **opts.reject { |k, _| k == :code })
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
