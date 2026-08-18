<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Ads ─────────────────────────────────────────────────────────────

class AdsResource
{
    public function __construct(private readonly Client $client) {}

    public function linkedinCompanyAudience(array $data): array
    {
        return $this->client->request('POST', '/ads/linkedin/company-audience', $data);
    }
}
