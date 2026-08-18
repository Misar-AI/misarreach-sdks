<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Workspaces ──────────────────────────────────────────────────────

class WorkspacesResource
{
    public function __construct(private readonly Client $client) {}

    public function list(): array
    {
        return $this->client->request('GET', '/workspaces');
    }

    public function create(array $data): array
    {
        return $this->client->request('POST', '/workspaces', $data);
    }

    public function listMembers(string $id): array
    {
        return $this->client->request('GET', "/workspaces/{$id}/members");
    }

    public function addMember(string $id, array $data): array
    {
        return $this->client->request('POST', "/workspaces/{$id}/members", $data);
    }

    public function removeMember(string $id, array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('DELETE', "/workspaces/{$id}/members{$qs}");
    }
}
