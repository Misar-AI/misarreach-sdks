<?php

declare(strict_types=1);

namespace MisarReach;

/**
 * Thrown when the MisarReach API returns a non-2xx HTTP response.
 */
class ApiError extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 0,
        public readonly ?string $code = null,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $status, $previous);
    }
}

/**
 * Thrown for HTTP 401/403 responses.
 */
class AuthError extends ApiError
{
    public function __construct(string $message, int $status = 401, ?\Throwable $previous = null)
    {
        parent::__construct($message, $status, 'unauthorized', $previous);
    }
}

/**
 * Thrown for HTTP 404 responses.
 */
class NotFoundError extends ApiError
{
    public function __construct(string $message, ?\Throwable $previous = null)
    {
        parent::__construct($message, 404, 'not_found', $previous);
    }
}

/**
 * Thrown for HTTP 429 responses. Carries the remaining wallet balance and
 * free-tier allowance when supplied by the API.
 */
class RateLimitError extends ApiError
{
    public function __construct(
        string $message,
        public readonly ?float $balance = null,
        public readonly ?int $freeRemaining = null,
        public readonly bool $upgrade = false,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, 429, $upgrade ? 'upgrade_required' : 'rate_limit', $previous);
    }
}

/**
 * Thrown when a network-level error prevents the request from completing,
 * or when the maximum number of retries is exhausted.
 */
class NetworkError extends ApiError
{
    public function __construct(string $message, ?\Throwable $previous = null)
    {
        parent::__construct($message, 0, 'network_error', $previous);
    }
}
