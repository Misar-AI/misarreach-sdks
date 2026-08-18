<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Contacts ────────────────────────────────────────────────────────

class ContactsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/contacts{$qs}");
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/contacts', $data);
    }

    public function get(string $id): array
    {
        return $this->client->request('GET', "/contacts/{$id}");
    }

    public function update(string $id, array $data): array
    {
        return $this->client->request('PATCH', "/contacts/{$id}", $data);
    }

    public function delete(string $id): array
    {
        return $this->client->request('DELETE', "/contacts/{$id}");
    }

    public function bulk(array $data): array
    {
        return $this->client->request('POST', '/contacts/bulk', $data);
    }

    public function import(array $data): array
    {
        return $this->client->request('POST', '/contacts/import', $data);
    }

    public function segments(): array
    {
        return $this->client->request('GET', '/contacts/segments');
    }

    public function stats(): array
    {
        return $this->client->request('GET', '/contacts/stats');
    }
}
