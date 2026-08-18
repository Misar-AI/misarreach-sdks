<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Campaigns ───────────────────────────────────────────────────────

class CampaignsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/campaigns{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/campaigns', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/campaigns/{$id}");
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/campaigns/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/campaigns/{$id}");
    }

    public function enqueue(string $id, array $data = []): array
    {
        return $this->client->request('POST', "/campaigns/{$id}/enqueue", $data);
    }
}
