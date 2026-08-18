<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Deals ───────────────────────────────────────────────────────────

class DealsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/deals{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/deals', $data);
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/deals/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/deals/{$id}");
    }

    public function activity(string $id): array
    {
        return $this->client->request('GET', "/deals/{$id}/activity");
    }

    public function suggestions(string $id): array
    {
        return $this->client->request('GET', "/deals/{$id}/suggestions");
    }

    /**
     * Apply one operation to many deals at once —
     * `['ids' => [...], 'op' => 'tag'|'untag'|'stage'|'delete', ...]`. Tag writes
     * are applied atomically server-side, so concurrent callers cannot lose a tag.
     */
    public function bulk(array $data): array
    {
        return $this->client->request('POST', '/deals/bulk', $data);
    }
}
