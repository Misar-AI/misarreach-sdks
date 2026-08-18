<?php

declare(strict_types=1);

namespace MisarReach;

class CampaignTemplatesResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/campaign-templates{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/campaign-templates', $data);
    }
}
