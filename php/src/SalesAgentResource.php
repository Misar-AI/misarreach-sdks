<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Sales Agent ─────────────────────────────────────────────────────

class SalesAgentResource
{
    public function __construct(private readonly Client $client) {}

    public function actions(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/sales-agent/actions{$qs}");
    }

    public function config(): array
    {
        return $this->client->request('GET', '/sales-agent/config');
    }

    public function updateConfig(array $data): array
    {
        return $this->client->request('PATCH', '/sales-agent/config', $data);
    }

    public function conversations(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/sales-agent/conversations{$qs}");
    }

    public function process(array $data): array
    {
        return $this->client->request('POST', '/sales-agent/process', $data);
    }
}
