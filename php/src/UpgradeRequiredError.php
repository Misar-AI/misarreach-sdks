<?php

declare(strict_types=1);

namespace MisarReach;

/**
 * A counted plan cap was hit.
 *
 * MisarReach answers 402 with `upgrade: true` when a cap is reached — searches,
 * results, autopilot runs, deals, seats, channels — and names the offending
 * counter. Retrying cannot help until the cap resets or the plan changes.
 *
 * Distinct from the 503 `retry: true` the server sends when it could not
 * *check* the quota: that one is retried, so "we do not know" is never mistaken
 * for "you are over your limit".
 */
class UpgradeRequiredError extends ApiError
{
    public function __construct(
        string $message,
        int $status = 402,
        /** The counter that was exhausted, e.g. "lead_searches". */
        public readonly ?string $feature = null,
        /** The cap on the current plan. */
        public readonly ?int $limit = null,
        /** Usage against that cap when the call was refused. */
        public readonly ?int $current = null,
        /** Absolute URL to the billing page. */
        public readonly ?string $upgradeUrl = null,
    ) {
        parent::__construct($message, $status, 'upgrade_required');
    }
}
