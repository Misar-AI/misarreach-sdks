<?php

declare(strict_types=1);

namespace MisarReach;

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
