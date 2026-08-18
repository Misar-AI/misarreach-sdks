<?php

declare(strict_types=1);

namespace MisarReach;

class NotificationsResource
{
    public function __construct(private readonly Client $client) {}

    public function list(array $params = []): array
    {
        $qs = $params ? '?' . http_build_query($params) : '';
        return $this->client->request('GET', "/notifications{$qs}");
    }

    /** Mark notifications read. Pass `['ids' => [...]]` or `['all' => true]`. */
    public function markRead(array $data): array
    {
        return $this->client->request('PATCH', '/notifications', $data);
    }
}
