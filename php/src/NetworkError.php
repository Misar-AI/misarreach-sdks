<?php

declare(strict_types=1);

namespace MisarReach;

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
