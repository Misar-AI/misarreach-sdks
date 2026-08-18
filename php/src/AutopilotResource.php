<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Autopilot ───────────────────────────────────────────────────────

class AutopilotResource
{
    public function __construct(private readonly Client $client) {}

    public function runs(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/autopilot/runs{$qs}");
    }

    public function start(array $data): array
    {
        return $this->client->request('POST', '/autopilot/start', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/autopilot/{$id}");
    }

    public function status(string $id): array
    {
        return $this->client->request('GET', "/autopilot/{$id}/status");
    }

    public function setStatus(string $id, array $data): array
    {
        return $this->client->request('POST', "/autopilot/{$id}/status", $data);
    }
}
