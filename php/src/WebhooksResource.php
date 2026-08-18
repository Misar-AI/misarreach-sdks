<?php

declare(strict_types=1);

namespace MisarReach;

class WebhooksResource
{
    public function __construct(private readonly Client $client) {}

    public function list(): array
    {
        return $this->client->request('GET', '/webhooks/endpoints');
    }

    /**
     * Register an endpoint. The response carries the signing secret exactly
     * once — store it then; it is not retrievable afterwards.
     */
    public function create(array $data): array
    {
        return $this->client->request('POST', '/webhooks/endpoints', $data);
    }
}
