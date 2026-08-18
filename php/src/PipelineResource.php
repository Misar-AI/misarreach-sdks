<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Pipeline ────────────────────────────────────────────────────────

class PipelineResource
{
    public function __construct(private readonly Client $client) {}

    public function get(): array
    {
        return $this->client->request('GET', '/pipeline');
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/pipeline', $data);
    }
}
