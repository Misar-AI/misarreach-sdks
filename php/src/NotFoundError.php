<?php

declare(strict_types=1);

namespace MisarReach;

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
