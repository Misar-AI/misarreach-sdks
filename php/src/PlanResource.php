<?php

declare(strict_types=1);

namespace MisarReach;

/**
 * The subscription behind the API key.
 *
 * Read this before an expensive run rather than discovering the ceiling through
 * an UpgradeRequiredError halfway through: a 402 says a call *was* refused,
 * whereas `usage` says what is left before anything is spent.
 */
class PlanResource
{
    public function __construct(private readonly Client $client) {}

    /**
     * GET /plan — plan, caps, per-feature usage and the upgrade offer.
     *
     * A null limit means unlimited, and `remaining` is null with it rather than
     * 0 — 0 would read as exhausted.
     *
     * @return array<string,mixed>
     */
    public function get(): array
    {
        return $this->client->request('GET', '/plan');
    }
}
