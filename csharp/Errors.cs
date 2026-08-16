namespace Misar.Reach;

/// <summary>
/// Thrown when the MisarReach API returns a non-2xx HTTP response.
/// </summary>
public class MisarReachException : Exception
{
    /// <summary>HTTP status code returned by the server (0 for network errors).</summary>
    public int Status { get; }

    /// <summary>Optional machine-readable error code from the response body.</summary>
    public string? Code { get; }

    public MisarReachException(int status, string message, string? code = null)
        : base($"MisarReachException({status}): {message}")
    {
        Status = status;
        Code = code;
    }

    public MisarReachException(int status, string message, Exception inner, string? code = null)
        : base($"MisarReachException({status}): {message}", inner)
    {
        Status = status;
        Code = code;
    }
}

/// <summary>Thrown for HTTP 401/403 responses.</summary>
public sealed class AuthException : MisarReachException
{
    public AuthException(int status, string message) : base(status, message, "unauthorized") { }
}

/// <summary>Thrown for HTTP 404 responses.</summary>
public sealed class NotFoundException : MisarReachException
{
    public NotFoundException(string message) : base(404, message, "not_found") { }
}

/// <summary>
/// Thrown for HTTP 429 responses. Carries remaining wallet balance and
/// free-tier allowance when supplied by the API.
/// </summary>
public class RateLimitException : MisarReachException
{
    public double? Balance { get; }
    public int? FreeRemaining { get; }

    public RateLimitException(string message, double? balance = null, int? freeRemaining = null)
        : base(429, message, "rate_limit")
    {
        Balance = balance;
        FreeRemaining = freeRemaining;
    }
}

/// <summary>
/// Thrown for HTTP 429 responses that require the caller to upgrade their plan
/// (<c>upgrade: true</c> in the response body).
/// </summary>
public sealed class UpgradeRequiredException : MisarReachException
{
    public UpgradeRequiredException(string message) : base(429, message, "upgrade_required") { }
}

/// <summary>
/// Thrown when a network-level error prevents the request from completing,
/// or when the maximum number of retries is exhausted.
/// </summary>
public sealed class MisarReachNetworkException : MisarReachException
{
    public MisarReachNetworkException(string message) : base(0, message, "network_error") { }

    public MisarReachNetworkException(string message, Exception inner)
        : base(0, message, inner, "network_error") { }
}
