<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Conversations ───────────────────────────────────────────────────

class ConversationsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/conversations{$qs}");
    }

    public function get(string $email): array
    {
        return $this->client->request('GET', '/conversations/' . rawurlencode($email));
    }

    public function reply(string $email, array $data): array
    {
        return $this->client->request('POST', '/conversations/' . rawurlencode($email) . '/reply', $data);
    }
}
