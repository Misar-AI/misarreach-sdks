<?php

declare(strict_types=1);

namespace MisarReach;

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
