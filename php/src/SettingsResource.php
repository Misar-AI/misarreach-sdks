<?php

declare(strict_types=1);

namespace MisarReach;

// ── Resource: Settings ────────────────────────────────────────────────────────

class SettingsResource
{
    public function __construct(private readonly Client $client) {}

    public function senderAddress(): array
    {
        return $this->client->request('GET', '/settings/sender-address');
    }

    public function setSenderAddress(array $data): array
    {
        return $this->client->request('PUT', '/settings/sender-address', $data);
    }
}
