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
        /** The API's string error code, e.g. `upgrade_required`. */
        public readonly ?string $errorCode = null,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $status, $previous);
    }
}
